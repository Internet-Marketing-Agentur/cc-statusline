#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;252m'  # light gray for default text
C_BAR_EMPTY='\033[38;5;246m'
C_WARN='\033[38;5;203m'  # red/orange warning
C_YELLOW='\033[38;5;178m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
# Shorten model name: "Claude Opus 4.6" → "Opus 4.6"
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"' | sed 's/^Claude //')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Build short path: ~/dir or ~/parent/dir for better orientation
short_path=""
if [[ -n "$cwd" ]]; then
    home="$HOME"
    if [[ "$cwd" == "$home" ]]; then
        short_path="~"
    elif [[ "$cwd" == "$home"/* ]]; then
        rel="${cwd#$home/}"
        # Show last 2 path components max
        depth=$(echo "$rel" | tr '/' '\n' | wc -l | tr -d ' ')
        if [[ $depth -le 2 ]]; then
            short_path="~/${rel}"
        else
            parent=$(basename "$(dirname "$cwd")")
            short_path="…/${parent}/${dir}"
        fi
    else
        short_path="$cwd"
    fi
fi

# Get context window info from JSON (Claude Code 2.1.6+)
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty | floor')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty | floor')

# Check if context data is available (not available at session start)
if [[ -z "$used_pct" || "$used_pct" == "null" ]]; then
    loading_bar=""
    for ((i=0; i<20; i++)); do loading_bar+="○"; done
    ctx="${C_BAR_EMPTY}${loading_bar}${C_RESET} ${C_GRAY}...${C_RESET}"
else
    [[ $used_pct -gt 100 ]] && used_pct=100

    used_tokens=$((max_context * used_pct / 100))
    used_k=$((used_tokens / 1000))

    # Build context bar (20 dots wide)
    bar_width=20
    filled=$(( used_pct * bar_width / 100 ))
    empty=$(( bar_width - filled ))

    # Color based on usage level
    bar_color=""
    if [[ $used_pct -ge 90 ]]; then bar_color="$C_WARN"
    elif [[ $used_pct -ge 70 ]]; then bar_color="$C_YELLOW"
    elif [[ $used_pct -ge 50 ]]; then bar_color="$C_ACCENT"
    else bar_color='\033[38;5;71m'  # green
    fi

    bar=""
    for ((i=0; i<filled; i++)); do bar+="●"; done
    empty_dots=""
    for ((i=0; i<empty; i++)); do empty_dots+="○"; done
    bar="${bar_color}${bar}${C_BAR_EMPTY}${empty_dots}${C_RESET}"

    if [[ -n "$remaining_pct" && "$remaining_pct" != "null" && $remaining_pct -le 20 ]]; then
        ctx="${bar} ${C_WARN}${used_k}k/${max_k}k (${used_pct}%) ⚠${C_RESET}"
    else
        ctx="${bar} ${C_GRAY}${used_k}k/${max_k}k (${used_pct}%)${C_RESET}"
    fi
fi

# Git info (only if inside a git repo)
git_info=""
if [[ -n "$cwd" ]] && git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    changed=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$changed" -eq 0 ]]; then
        git_info="⎇ ${branch} ✓"
    else
        git_info="⎇ ${branch} ${changed}△"
    fi
fi

# ===== Usage limits (5h / 7d) via Anthropic OAuth API =====

# Build a colored usage bar (6 dots wide)
# Color: green <50%, yellow 50-69%, orange 70-89%, red 90%+
build_usage_bar() {
    local pct=$1
    local width=6
    [[ $pct -lt 0 ]] && pct=0
    [[ $pct -gt 100 ]] && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local bar_color
    if [[ $pct -ge 90 ]]; then bar_color="$C_WARN"
    elif [[ $pct -ge 70 ]]; then bar_color="$C_YELLOW"
    elif [[ $pct -ge 50 ]]; then bar_color="$C_ACCENT"
    else bar_color='\033[38;5;71m'  # green
    fi

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="●"; done
    local empty_dots=""
    for ((i=0; i<empty; i++)); do empty_dots+="○"; done

    printf "${bar_color}${bar}${C_BAR_EMPTY}${empty_dots}${C_RESET}"
}

# Convert ISO 8601 timestamp to local time string
# Works with both GNU date (coreutils) and BSD date (macOS)
format_reset_time() {
    local iso_str="$1"
    local style="$2"  # "time" or "datetime"
    [[ -z "$iso_str" || "$iso_str" == "null" ]] && return

    local epoch
    # GNU date: handles ISO 8601 natively
    epoch=$(date -d "$iso_str" +%s 2>/dev/null)
    if [[ -z "$epoch" ]]; then
        # BSD date fallback
        local stripped="${iso_str%%.*}"
        stripped="${stripped%%Z}"
        stripped="${stripped%%+*}"
        if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]]; then
            epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        else
            epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        fi
    fi
    [[ -z "$epoch" ]] && return

    case "$style" in
        time)
            date -d "@$epoch" +"%H:%M" 2>/dev/null || date -j -r "$epoch" +"%H:%M" 2>/dev/null
            ;;
        datetime)
            date -d "@$epoch" +"%-d.%-m. %H:%M" 2>/dev/null || date -j -r "$epoch" +"%-d.%-m. %H:%M" 2>/dev/null
            ;;
    esac
}

# Get OAuth token from macOS Keychain
# The keychain blob is hex-encoded with a leading control byte,
# so we decode and extract the token via regex instead of jq.
get_oauth_token() {
    if [[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi
    if command -v security >/dev/null 2>&1; then
        local token
        token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
            | grep -oE '"accessToken":"[^"]+"' \
            | head -1 \
            | sed 's/"accessToken":"//;s/"$//')
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    echo ""
}

# Fetch usage data with 60s file cache
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude 2>/dev/null

needs_refresh=true
usage_data=""

if [[ -f "$cache_file" ]]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [[ $cache_age -lt $cache_max_age ]]; then
        needs_refresh=false
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

if $needs_refresh; then
    token=$(get_oauth_token)
    if [[ -n "$token" && "$token" != "null" ]]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [[ -n "$response" ]] && echo "$response" | jq . >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    # Fall back to stale cache
    if [[ -z "$usage_data" && -f "$cache_file" ]]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

# Build usage limit segments
usage_info=""
if [[ -n "$usage_data" ]] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    # 5-hour limit
    five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_reset=$(format_reset_time "$five_reset_iso" "time")
    five_bar=$(build_usage_bar "$five_pct")

    usage_info+=" | ${C_GRAY}5h${C_RESET} ${five_bar} ${C_GRAY}${five_pct}%${C_RESET}"
    [[ -n "$five_reset" ]] && usage_info+=" ${C_BAR_EMPTY}@${five_reset}${C_RESET}"

    # 7-day limit
    seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_reset=$(format_reset_time "$seven_reset_iso" "datetime")
    seven_bar=$(build_usage_bar "$seven_pct")

    usage_info+=" | ${C_GRAY}7d${C_RESET} ${seven_bar} ${C_GRAY}${seven_pct}%${C_RESET}"
    [[ -n "$seven_reset" ]] && usage_info+=" ${C_BAR_EMPTY}@${seven_reset}${C_RESET}"
fi

# Build output: Model | Directory | Context | Git | 5h | 7d
output="${C_ACCENT}${model}${C_GRAY}"
[[ -n "$short_path" ]] && output+=" | 📂 ${short_path}"
output+=" | ${ctx}"
[[ -n "$git_info" ]] && output+=" | ${C_GRAY}${git_info}"
output+="${usage_info}"
output+="${C_RESET}"

printf '%b\n' "$output"

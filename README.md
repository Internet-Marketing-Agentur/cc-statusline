# Claude Code Status Line

Erweiterte Statuszeile für Claude Code mit Kontext-Anzeige, Git-Info und API-Usage-Limits.

![Screenshot](screenshot.png)

## Anzeige

```
Opus 4.6 | 📂 …/Code/Projekt | ●●○○○○○○○○○○○○○○○○○○ 24k/200k (12%) | ⎇ main ✓ | 5h ○○○○○○ 2% @19:00 | 7d ●○○○○○ 20% @6.3. 22:00
```

### Segmente

| Segment | Beschreibung |
|---------|-------------|
| **Modell** | Aktuelles Claude-Modell (z.B. Opus 4.6) |
| **Verzeichnis** | Aktuelles Arbeitsverzeichnis (gekürzt) |
| **Context** | Fortschrittsbalken + Token-Verbrauch (20 Punkte breit) |
| **Git** | Branch + Anzahl geänderter Dateien |
| **5h-Limit** | 5-Stunden-Nutzungslimit mit Reset-Uhrzeit |
| **7d-Limit** | 7-Tage-Nutzungslimit mit Reset-Datum |

### Farbcodierung (Fortschrittsbalken)

- **Grün** (<50%) — alles entspannt
- **Blau/Accent** (50-69%) — wird voller
- **Gelb** (70-89%) — Achtung
- **Rot** (90%+) — kritisch

## Voraussetzungen

- `jq` — JSON-Verarbeitung
- `curl` — API-Aufrufe
- `xxd` — Keychain-Dekodierung (macOS)
- Claude Code mit OAuth-Login (für Usage-Daten)

## Installation

### 1. Script kopieren

```bash
# Verzeichnis anlegen
mkdir -p ~/.claude/scripts/statusline

# Script herunterladen
curl -fsSL https://raw.githubusercontent.com/Internet-Marketing-Agentur/cc-statusline/main/statusline.sh \
  -o ~/.claude/scripts/statusline/statusline.sh

# Ausführbar machen
chmod +x ~/.claude/scripts/statusline/statusline.sh
```

Alternativ per Git:

```bash
git clone https://github.com/Internet-Marketing-Agentur/cc-statusline.git /tmp/cc-statusline
cp /tmp/cc-statusline/statusline.sh ~/.claude/scripts/statusline/statusline.sh
chmod +x ~/.claude/scripts/statusline/statusline.sh
rm -rf /tmp/cc-statusline
```

### 2. Claude Code konfigurieren

In `~/.claude/settings.json` die Statusline aktivieren:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/statusline/statusline.sh"
  }
}
```

### 3. Claude Code neu starten

Die Statusline erscheint nach dem nächsten Start von Claude Code automatisch am unteren Terminalrand.

## Konfiguration

### Farbthema

Zeile 5 im Skript ändern:

```bash
COLOR="blue"  # gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
```

### Kompatibilität

- GNU coreutils (`stat -c`, `date -d`) mit BSD-Fallback
- macOS Keychain (hex-kodierter Blob) + `CLAUDE_CODE_OAUTH_TOKEN` Env-Variable
- Usage-Daten werden 60 Sekunden in `/tmp/claude/statusline-usage-cache.json` gecacht

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/Internet-Marketing-Agentur/cc-statusline/main/statusline.sh \
  -o ~/.claude/scripts/statusline/statusline.sh
```

## Inspiration

Basierend auf [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine).

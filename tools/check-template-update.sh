#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_HOME="${MINDFlAYER_HOME:-$HOME/.ai-toolkit}"
TEMPLATE="$TOOLKIT_HOME/templates/AGENTS.md"
[ -f AGENTS.md ] || { printf 'No AGENTS.md in current directory.\n'; exit 1; }
[ -f "$TEMPLATE" ] || { printf 'Template not found: %s\n' "$TEMPLATE" >&2; exit 1; }
installed="$(sed -n 's/.*template: AGENTS | version: \([^ ]*\).*/\1/p' AGENTS.md | head -1)"
current="$(sed -n 's/.*template: AGENTS | version: \([^ ]*\).*/\1/p' "$TEMPLATE" | head -1)"
[ -n "$installed" ] || { printf 'AGENTS.md is not toolkit-template based.\n'; exit 0; }
printf 'Installed schema: %s\nCurrent schema:   %s\n' "$installed" "$current"
[ "$installed" = "$current" ]

#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_HOME="${MINDFlAYER_HOME:-$HOME/.ai-toolkit}"
SOURCE="$TOOLKIT_HOME/skills"
TARGET="./.claude/skills"
MANIFEST="$TOOLKIT_HOME/manifest.tsv"

[ -f "$MANIFEST" ] || { printf 'error: manifest not found: %s\n' "$MANIFEST" >&2; exit 1; }
[ -d "$SOURCE" ] || { printf 'error: skill source not found: %s\n' "$SOURCE" >&2; exit 1; }
[ -d "$TARGET" ] || { printf 'error: project skills not found: %s\n' "$TARGET" >&2; exit 1; }

status=0
while IFS=$'\t' read -r path type version _consumers _ownership; do
  [ "$type" = skill ] || continue
  name="${path#skills/}"; name="${name%/SKILL.md}"
  if [ ! -d "$TARGET/$name" ]; then printf '%-24s MISSING (toolkit %s)\n' "$name" "$version"; status=1
  elif diff -qr "$SOURCE/$name" "$TARGET/$name" >/dev/null 2>&1; then printf '%-24s in sync (%s)\n' "$name" "$version"
  else printf '%-24s DRIFTED (%s, full directory)\n' "$name" "$version"; status=1
  fi
done < "$MANIFEST"
exit "$status"

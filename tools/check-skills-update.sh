#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_HOME="${MINDFLAYER_HOME:-${MINDFlAYER_HOME:-$HOME/.ai-toolkit}}"
SOURCE="$TOOLKIT_HOME/skills"
MANIFEST="$TOOLKIT_HOME/manifest.tsv"
TARGETS=()

[ -f "$MANIFEST" ] || { printf 'error: manifest not found: %s\n' "$MANIFEST" >&2; exit 1; }
[ -d "$SOURCE" ] || { printf 'error: skill source not found: %s\n' "$SOURCE" >&2; exit 1; }

for candidate in ./.claude/skills ./.agents/skills; do
  [ ! -d "$candidate" ] || TARGETS+=("$candidate")
done
[ "${#TARGETS[@]}" -gt 0 ] || {
  printf 'error: no managed project skill roots found (.claude/skills or .agents/skills)\n' >&2
  exit 1
}

status=0
for target in "${TARGETS[@]}"; do
  printf '%s\n' "$target"
  while IFS=$'\t' read -r path type version _consumers _ownership; do
    [ "$type" = skill ] || continue
    name="${path#skills/}"
    name="${name%/SKILL.md}"
    if [ ! -d "$target/$name" ]; then
      printf '%-24s MISSING (toolkit %s)\n' "$name" "$version"
      status=1
    elif diff -qr "$SOURCE/$name" "$target/$name" >/dev/null 2>&1; then
      printf '%-24s in sync (%s)\n' "$name" "$version"
    else
      printf '%-24s DRIFTED (%s, full directory)\n' "$name" "$version"
      status=1
    fi
  done < "$MANIFEST"
done

exit "$status"

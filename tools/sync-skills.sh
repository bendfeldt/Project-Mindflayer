#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_HOME="${MINDFlAYER_HOME:-$HOME/.ai-toolkit}"
SOURCE="$TOOLKIT_HOME/skills"
TARGET="./.claude/skills"
MANIFEST="$TOOLKIT_HOME/manifest.tsv"
DRY_RUN=0
REPLACE=0

for argument in "$@"; do
  case "$argument" in --dry-run) DRY_RUN=1 ;; --force) REPLACE=1 ;; --help|-h) sed -n '1,18p' "$0"; exit 0 ;; *) printf 'error: unknown option: %s\n' "$argument" >&2; exit 1 ;; esac
done
[ -f "$MANIFEST" ] || { printf 'error: manifest not found: %s\n' "$MANIFEST" >&2; exit 1; }
mkdir -p "$TARGET"

while IFS=$'\t' read -r path type version _consumers _ownership; do
  [ "$type" = skill ] || continue
  name="${path#skills/}"; name="${name%/SKILL.md}"
  [ -d "$SOURCE/$name" ] || { printf 'error: missing source skill %s\n' "$name" >&2; exit 1; }
  if [ ! -d "$TARGET/$name" ]; then action=add
  elif diff -qr "$SOURCE/$name" "$TARGET/$name" >/dev/null 2>&1; then printf '= %s\n' "$name"; continue
  elif [ "$REPLACE" -eq 1 ]; then action=replace
  else printf '! preserve %s (drifted; use --force)\n' "$name"; continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then printf 'would %s %s\n' "$action" "$name"; continue; fi
  if [ "$action" = replace ]; then
    backup="$TARGET/$name.bak.$(date '+%Y%m%d%H%M%S')"; cp -R "$TARGET/$name" "$backup"
    [ -n "$TARGET" ] && [ "$TARGET" != / ] || { printf 'error: unsafe target\n' >&2; exit 1; }
    rm -rf "${TARGET:?}/$name"
  fi
  mkdir -p "$TARGET/$name"; cp -R "$SOURCE/$name/." "$TARGET/$name/"
  printf '+ %s (%s)\n' "$name" "$version"
done < "$MANIFEST"

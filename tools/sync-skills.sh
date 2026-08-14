#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_HOME="${MINDFLAYER_HOME:-${MINDFlAYER_HOME:-$HOME/.ai-toolkit}}"
SOURCE="$TOOLKIT_HOME/skills"
MANIFEST="$TOOLKIT_HOME/manifest.tsv"
TARGETS=()
DRY_RUN=0
REPLACE=0

for argument in "$@"; do
  case "$argument" in
    --dry-run) DRY_RUN=1 ;;
    --force) REPLACE=1 ;;
    --help|-h) sed -n '1,24p' "$0"; exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$argument" >&2; exit 1 ;;
  esac
done

[ -f "$MANIFEST" ] || { printf 'error: manifest not found: %s\n' "$MANIFEST" >&2; exit 1; }
[ -d "$SOURCE" ] || { printf 'error: skill source not found: %s\n' "$SOURCE" >&2; exit 1; }

for candidate in ./.claude/skills ./.agents/skills; do
  [ ! -d "$candidate" ] || TARGETS+=("$candidate")
done
[ "${#TARGETS[@]}" -gt 0 ] || {
  printf 'error: no managed project skill roots found (.claude/skills or .agents/skills)\n' >&2
  exit 1
}

for target in "${TARGETS[@]}"; do
  printf '%s\n' "$target"
  while IFS=$'\t' read -r path type version _consumers _ownership; do
    [ "$type" = skill ] || continue
    name="${path#skills/}"
    name="${name%/SKILL.md}"
    [ -d "$SOURCE/$name" ] || { printf 'error: missing source skill %s\n' "$name" >&2; exit 1; }

    if [ ! -d "$target/$name" ]; then
      action=add
    elif diff -qr "$SOURCE/$name" "$target/$name" >/dev/null 2>&1; then
      printf '= %s\n' "$name"
      continue
    elif [ "$REPLACE" -eq 1 ]; then
      action=replace
    else
      printf '! preserve %s (drifted; use --force)\n' "$name"
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'would %s %s\n' "$action" "$name"
      continue
    fi

    if [ "$action" = replace ]; then
      backup="$target/$name.bak.$(date '+%Y%m%d%H%M%S')"
      cp -R "$target/$name" "$backup"
      [ -n "$target" ] && [ "$target" != / ] || {
        printf 'error: unsafe target\n' >&2
        exit 1
      }
      rm -rf "${target:?}/$name"
    fi
    mkdir -p "$target/$name"
    cp -R "$SOURCE/$name/." "$target/$name/"
    printf '+ %s (%s)\n' "$name" "$version"
  done < "$MANIFEST"
done

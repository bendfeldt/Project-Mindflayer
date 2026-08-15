#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
[ -n "$MODE" ] || { printf 'error: lifecycle mode required\n' >&2; exit 1; }
shift

TOOLKIT_HOME="${MINDFLAYER_HOME:-${MINDFlAYER_HOME:-$HOME/.ai-toolkit}}"
SOURCE="$TOOLKIT_HOME/skills"
MANIFEST="$TOOLKIT_HOME/manifest.tsv"
OWNERSHIP_FILE="$(pwd)/.mindflayer-managed.tsv"
DRY_RUN=0
REPLACE=0
STATUS=0

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  case "$MODE" in
    check) printf 'Usage: check-skills-update.sh\n' ;;
    sync) printf 'Usage: sync-skills.sh [--dry-run] [--force]\n' ;;
  esac
}

parse_arguments() {
  case "$MODE" in
    check)
      case "$#" in
        0) ;;
        1) case "$1" in --help|-h) usage; exit 0 ;; *) fail "unknown option: $1" ;; esac ;;
        *) fail "check-skills-update.sh accepts no arguments" ;;
      esac
      ;;
    sync)
      while [ $# -gt 0 ]; do
        case "$1" in
          --dry-run) DRY_RUN=1 ;;
          --force) REPLACE=1 ;;
          --help|-h) usage; exit 0 ;;
          *) fail "unknown option: $1" ;;
        esac
        shift
      done
      ;;
    *) fail "unknown lifecycle mode: $MODE" ;;
  esac
}

managed_roots() {
  awk -F '\t' '
    $2 == "file" && $1 ~ /\/skills\/[^\/]+\/SKILL[.]md$/ {
      root=$1
      sub(/\/[^\/]+\/SKILL[.]md$/, "", root)
      if (root ~ /^\// || root ~ /(^|\/)\.\.($|\/)/ || root == "." || root == "") {
        printf "error: unsafe managed skill root: %s\n", root > "/dev/stderr"
        unsafe=1
      } else if (!seen[root]++) {
        print root
      }
    }
    END { exit unsafe ? 1 : 0 }
  ' "$OWNERSHIP_FILE"
}

backup_path() {
  local path="$1" candidate suffix=0
  candidate="${path}.bak.$(date '+%Y%m%d%H%M%S')"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    suffix=$((suffix + 1))
    candidate="${path}.bak.$(date '+%Y%m%d%H%M%S').$suffix"
  done
  printf '%s' "$candidate"
}

check_skill() {
  local target="$1" name="$2" version="$3"
  if [ ! -d "$target/$name" ]; then
    printf '%-24s MISSING (toolkit %s)\n' "$name" "$version"
    STATUS=1
  elif diff -qr "$SOURCE/$name" "$target/$name" >/dev/null 2>&1; then
    printf '%-24s in sync (%s)\n' "$name" "$version"
  else
    printf '%-24s DRIFTED (%s, full directory)\n' "$name" "$version"
    STATUS=1
  fi
}

sync_skill() {
  local target="$1" name="$2" version="$3" action backup
  if [ ! -d "$target/$name" ]; then
    action=add
  elif diff -qr "$SOURCE/$name" "$target/$name" >/dev/null 2>&1; then
    printf '= %s\n' "$name"
    return
  elif [ "$REPLACE" -eq 1 ]; then
    action=replace
  else
    printf '! preserve %s (drifted; use --force)\n' "$name"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would %s %s\n' "$action" "$name"
    return
  fi

  if [ "$action" = replace ]; then
    backup="$(backup_path "$target/$name")"
    cp -R "$target/$name" "$backup"
    rm -rf "${target:?}/$name"
  fi
  mkdir -p "$target/$name"
  cp -R "$SOURCE/$name/." "$target/$name/"
  printf '+ %s (%s)\n' "$name" "$version"
}

main() {
  local roots target path type version name
  parse_arguments "$@"
  [ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
  [ -d "$SOURCE" ] || fail "skill source not found: $SOURCE"
  [ -f "$OWNERSHIP_FILE" ] || fail "ownership record not found: $OWNERSHIP_FILE"
  roots="$(managed_roots)" || fail "ownership record contains unsafe skill paths"
  [ -n "$roots" ] || fail "no managed project skill roots found in $OWNERSHIP_FILE"

  while IFS= read -r target; do
    printf '%s\n' "$target"
    while IFS=$'\t' read -r path type version _consumers _ownership; do
      [ "$type" = skill ] || continue
      name="${path#skills/}"
      name="${name%/SKILL.md}"
      if [ -z "$name" ] || [ "${name#*/}" != "$name" ]; then
        fail "unsafe skill name in manifest: $name"
      fi
      [ -d "$SOURCE/$name" ] || fail "missing source skill: $name"
      if [ "$MODE" = check ]; then
        check_skill "$target" "$name" "$version"
      else
        sync_skill "$target" "$name" "$version"
      fi
    done < "$MANIFEST"
  done <<< "$roots"

  exit "$STATUS"
}

main "$@"

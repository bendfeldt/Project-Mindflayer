#!/usr/bin/env bash
set -euo pipefail

MODE=""
CONFIRM=0
FORCE=0
REMOVED=0
PRESERVED=0

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: uninstall.sh (--global | --project) [--confirm] [--force]

Dry-run is the default. --confirm performs verified removal. Modified regular
files are preserved unless --force is supplied; forced removal backs them up.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global|--project)
      requested="${1#--}"
      [ -z "$MODE" ] || [ "$MODE" = "$requested" ] || fail "--global and --project are mutually exclusive"
      MODE="$requested"
      ;;
    --confirm) CONFIRM=1 ;;
    --force) FORCE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
  shift
done
[ -n "$MODE" ] || fail "specify --global or --project"

fingerprint() { cksum "$1" | awk '{print $1 ":" $2}'; }
backup() {
  local path="$1" candidate suffix=0
  candidate="${path}.bak.$(date '+%Y%m%d%H%M%S')"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do suffix=$((suffix + 1)); candidate="${path}.bak.$(date '+%Y%m%d%H%M%S').$suffix"; done
  cp -R "$path" "$candidate"
  printf ' backed up: %s\n' "$candidate"
}

remove_recorded() {
  local path="$1" kind="$2" proof="$3"
  if [ "$kind" = line ]; then
    [ -f "$path" ] || return
    if [ "$CONFIRM" -eq 1 ]; then
      temporary="${path}.mindflayer.tmp"
      awk -v value="$proof" '$0 != value {print}' "$path" > "$temporary"
      mv "$temporary" "$path"
      [ -s "$path" ] || rm -f "$path"
      printf ' removed line: %s from %s\n' "$proof" "$path"
    else
      printf ' would remove line: %s from %s\n' "$proof" "$path"
    fi
    REMOVED=$((REMOVED + 1)); return
  elif [ "$kind" = directory ]; then
    [ -d "$path" ] || return
    if [ -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      printf ' preserve: %s (not empty)\n' "$path"; PRESERVED=$((PRESERVED + 1)); return
    fi
    if [ "$CONFIRM" -eq 1 ]; then rmdir "$path"; printf ' removed: %s\n' "$path"; else printf ' would remove: %s\n' "$path"; fi
    REMOVED=$((REMOVED + 1)); return
  elif [ "$kind" = symlink ]; then
    if [ ! -L "$path" ] || [ "$(readlink "$path")" != "$proof" ]; then
      printf ' preserve: %s (symlink target changed)\n' "$path"; PRESERVED=$((PRESERVED + 1)); return
    fi
  elif [ "$kind" = file ]; then
    [ -f "$path" ] || return
    if [ "$(fingerprint "$path")" != "$proof" ]; then
      if [ "$FORCE" -ne 1 ]; then printf ' preserve: %s (modified)\n' "$path"; PRESERVED=$((PRESERVED + 1)); return; fi
      [ "$CONFIRM" -ne 1 ] || backup "$path"
    fi
  else
    printf ' preserve: %s (unknown ownership class)\n' "$path"; PRESERVED=$((PRESERVED + 1)); return
  fi

  if [ "$CONFIRM" -eq 1 ]; then rm -f "$path"; printf ' removed: %s\n' "$path"; else printf ' would remove: %s\n' "$path"; fi
  REMOVED=$((REMOVED + 1))
}

prune_empty_parents() {
  local path="$1" stop="$2" parent
  parent="$(dirname "$path")"
  while [ "$parent" != "$stop" ] && [ "$parent" != / ] && [ -d "$parent" ]; do
    rmdir "$parent" 2>/dev/null || break
    parent="$(dirname "$parent")"
  done
}

if [ "$MODE" = global ]; then
  STATE="$HOME/.ai-toolkit/managed.tsv"
  STOP="$HOME"
else
  STATE="$(pwd)/.mindflayer-managed.tsv"
  STOP="$(pwd)"
fi

[ -f "$STATE" ] || fail "ownership record not found: $STATE"

# Children are removed before parents; the state file itself is removed last.
reverse_state="$(mktemp)"
trap 'rm -f "$reverse_state"' EXIT
awk '{rows[NR]=$0} END {for (i=NR; i>=1; i--) print rows[i]}' "$STATE" > "$reverse_state"
while IFS=$'\t' read -r path kind proof; do
  [ -n "$path" ] || continue
  remove_recorded "$path" "$kind" "$proof"
  [ "$CONFIRM" -ne 1 ] || prune_empty_parents "$path" "$STOP"
done < "$reverse_state"

if [ "$CONFIRM" -eq 1 ] && [ "$PRESERVED" -eq 0 ]; then
  rm -f "$STATE"
  if [ "$MODE" = global ]; then rmdir "$HOME/.ai-toolkit" 2>/dev/null || true; fi
elif [ "$CONFIRM" -eq 1 ]; then
  printf ' ownership record retained for preserved artifacts: %s\n' "$STATE"
else
  printf ' ownership record retained: %s\n' "$STATE"
fi
printf 'Summary: %d removable, %d preserved\n' "$REMOVED" "$PRESERVED"

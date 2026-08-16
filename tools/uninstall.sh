#!/usr/bin/env bash
set -euo pipefail

MODE=""
CONFIRM=0
FORCE=0
REMOVED=0
PRESERVED=0
PROJECT_ROOT=""
HOME_ROOT=""
SAFE_PATH=""
SAFE_ROOT=""

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

canonicalize_owned_path() {
  local recorded="$1" candidate parent component suffix physical trimmed
  case "$recorded" in *$'\t'*|*$'\n'*|*$'\r'*|'') return 1 ;; esac
  case "$recorded" in
    /*) candidate="$recorded" ;;
    *) [ "$MODE" = project ] || return 1; candidate="$PROJECT_ROOT/$recorded" ;;
  esac
  trimmed="${candidate#/}"
  case "/$trimmed/" in *'//'*) return 1 ;; *'/./'*|*'/../'*) return 1 ;; esac
  parent="$(dirname "$candidate")"
  suffix="/$(basename "$candidate")"
  while [ ! -d "$parent" ]; do
    component="$(basename "$parent")"
    [ "$component" != / ] && [ "$component" != . ] || return 1
    suffix="/$component$suffix"
    candidate="$(dirname "$parent")"
    [ "$candidate" != "$parent" ] || return 1
    parent="$candidate"
  done
  physical="$(cd -P "$parent" && pwd -P)" || return 1
  SAFE_PATH="$physical$suffix"
}

resolve_owned_path() {
  local recorded="$1"
  canonicalize_owned_path "$recorded" || fail "unsafe ownership path: $recorded"
  if [ "$MODE" = project ]; then
    case "$SAFE_PATH" in
      "$PROJECT_ROOT"/*) SAFE_ROOT="$PROJECT_ROOT" ;;
      *) fail "ownership path escapes project root: $recorded" ;;
    esac
    return
  fi
  case "$SAFE_PATH" in
    "$HOME_ROOT/.ai-toolkit"/*) SAFE_ROOT="$HOME_ROOT/.ai-toolkit" ;;
    "$HOME_ROOT/.claude"/*) SAFE_ROOT="$HOME_ROOT/.claude" ;;
    "$HOME_ROOT/.codex"/*) SAFE_ROOT="$HOME_ROOT/.codex" ;;
    "$HOME_ROOT/.gemini"/*) SAFE_ROOT="$HOME_ROOT/.gemini" ;;
    "$HOME_ROOT/.cursor"/*) SAFE_ROOT="$HOME_ROOT/.cursor" ;;
    "$HOME_ROOT/.copilot"/*) SAFE_ROOT="$HOME_ROOT/.copilot" ;;
    "$HOME_ROOT/.agents"/*) SAFE_ROOT="$HOME_ROOT/.agents" ;;
    *) fail "ownership path escapes global managed roots: $recorded" ;;
  esac
}

validate_ownership_file() {
  local path kind proof extra
  [ ! -L "$STATE" ] || fail "ownership record must not be a symlink: $STATE"
  [ -f "$STATE" ] || fail "ownership record not found: $STATE"
  while IFS=$'\t' read -r path kind proof extra; do
    [ -n "$path" ] || fail "ownership record contains an empty path"
    [ -z "${extra:-}" ] || fail "ownership record must contain exactly three fields: $path"
    [ -n "$proof" ] || fail "ownership record contains empty evidence: $path"
    case "$kind" in file|symlink|directory|line) ;; *) fail "unknown ownership class for $path: $kind" ;; esac
    resolve_owned_path "$path"
  done < "$STATE"
}
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
      temporary="$(mktemp "${path}.mindflayer.tmp.XXXXXX")"
      chmod 600 "$temporary"
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

HOME_ROOT="$(cd -P "$HOME" && pwd -P)"
if [ "$MODE" = global ]; then
  STATE="$HOME/.ai-toolkit/managed.tsv"
else
  PROJECT_ROOT="$(pwd -P)"
  STATE="$PROJECT_ROOT/.mindflayer-managed.tsv"
fi

validate_ownership_file

# Children are removed before parents; the state file itself is removed last.
reverse_state="$(mktemp "${TMPDIR:-/tmp}/mindflayer-uninstall.XXXXXX")"
chmod 600 "$reverse_state"
trap 'rm -f "$reverse_state"' EXIT
awk '{rows[NR]=$0} END {for (i=NR; i>=1; i--) print rows[i]}' "$STATE" > "$reverse_state"
while IFS=$'\t' read -r path kind proof; do
  [ -n "$path" ] || continue
  resolve_owned_path "$path"
  artifact="$SAFE_PATH"
  stop="$SAFE_ROOT"
  remove_recorded "$artifact" "$kind" "$proof"
  [ "$CONFIRM" -ne 1 ] || prune_empty_parents "$artifact" "$stop"
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

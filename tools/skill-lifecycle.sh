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
PLATFORM=""
PROJECT_ROOT=""
SAFE_PATH=""

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_manifest() {
  awk -F '\t' '
    function invalid_list(value, values, count, i) {
      if (value == "" || value ~ /^,/ || value ~ /,$/ || value ~ /,,/) return 1
      delete values
      delete list_seen
      count = split(value, values, ",")
      for (i = 1; i <= count; i++) if (list_seen[values[i]]++) return 1
      return 0
    }
    $1 !~ /^#/ && NF {
      if (NF != 6) exit 2
      if ($1 == "" || $1 ~ /^\// || $1 ~ /\\/ || $1 ~ /\/\// ||
          $1 ~ /(^|\/)\.\.?($|\/)/ || $1 ~ /\/$/ || path_seen[$1]++) exit 2
      if ($2 !~ /^(baseline|decision|document|license|manifest|registry|script|setting|shim|skill|skill-resource|template)$/) exit 2
      if ($3 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || invalid_list($4)) exit 2
      consumer_count = split($4, consumers, ",")
      for (consumer_index = 1; consumer_index <= consumer_count; consumer_index++) {
        if (consumers[consumer_index] !~ /^(global|project|project:skills|global:(claude|codex|gemini|cursor|copilot)|project:(claude|gemini)|project:claude:(terraform|databricks|fabric))$/) exit 2
      }
      if ($5 !~ /^(managed-file|managed-tree)$/ || invalid_list($6)) exit 2
      platform_count = split($6, platforms, ",")
      for (platform_index = 1; platform_index <= platform_count; platform_index++) {
        if (platforms[platform_index] !~ /^(linux|macos|windows)$/) exit 2
      }
      rows++
    }
    END { if (!rows) exit 2 }
  ' "$MANIFEST" || fail "manifest.tsv failed strict six-field validation"
}

resolve_owned_path() {
  local recorded="$1" candidate parent component suffix physical trimmed
  case "$recorded" in *$'\t'*|*$'\n'*|*$'\r'*|'') fail "unsafe ownership path: $recorded" ;; esac
  case "$recorded" in /*) candidate="$recorded" ;; *) candidate="$PROJECT_ROOT/$recorded" ;; esac
  trimmed="${candidate#/}"
  case "/$trimmed/" in *'//'*) fail "unsafe ownership path: $recorded" ;; *'/./'*|*'/../'*) fail "unsafe ownership path: $recorded" ;; esac
  parent="$(dirname "$candidate")"
  suffix="/$(basename "$candidate")"
  while [ ! -d "$parent" ]; do
    component="$(basename "$parent")"
    [ "$component" != / ] && [ "$component" != . ] || fail "unsafe ownership path: $recorded"
    suffix="/$component$suffix"
    candidate="$(dirname "$parent")"
    [ "$candidate" != "$parent" ] || fail "unsafe ownership path: $recorded"
    parent="$candidate"
  done
  physical="$(cd -P "$parent" && pwd -P)" || fail "cannot resolve ownership path: $recorded"
  SAFE_PATH="$physical$suffix"
  case "$SAFE_PATH" in "$PROJECT_ROOT"/*) ;; *) fail "ownership path escapes project root: $recorded" ;; esac
}

validate_ownership_file() {
  local path kind proof extra
  [ ! -L "$OWNERSHIP_FILE" ] || fail "ownership record must not be a symlink: $OWNERSHIP_FILE"
  while IFS=$'\t' read -r path kind proof extra; do
    [ -n "$path" ] || fail "ownership record contains an empty path"
    [ -z "${extra:-}" ] || fail "ownership record must contain exactly three fields: $path"
    [ -n "$proof" ] || fail "ownership record contains empty evidence: $path"
    case "$kind" in file|symlink|directory|line) ;; *) fail "unknown ownership class for $path: $kind" ;; esac
    resolve_owned_path "$path"
  done < "$OWNERSHIP_FILE"
}

ownership_temporary() {
  local temporary
  temporary="$(mktemp "${OWNERSHIP_FILE}.tmp.XXXXXX")" || fail "cannot create ownership temporary"
  chmod 600 "$temporary"
  printf '%s' "$temporary"
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

consumer_includes_project_skills() {
  case ",$1," in
    *,project:skills,*) return 0 ;;
    *) return 1 ;;
  esac
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM=macos ;;
    Linux) PLATFORM=linux ;;
    *) fail "unsupported platform: $(uname -s)" ;;
  esac
}

validate_platforms() {
  local path="$1" platforms="$2" remaining token seen=","
  [ -n "$platforms" ] || fail "missing platforms in manifest: $path"
  case "$platforms" in ,*|*,|*,,*) fail "invalid platforms in manifest: $path" ;; esac
  remaining="$platforms"
  while :; do
    token="${remaining%%,*}"
    case "$token" in linux|macos|windows) ;; *) fail "invalid platform in manifest: $path ($token)" ;; esac
    case "$seen" in *,$token,*) fail "duplicate platform in manifest: $path ($token)" ;; esac
    seen="${seen}${token},"
    [ "$remaining" = "$token" ] && break
    remaining="${remaining#*,}"
  done
}

platform_includes_current() {
  case ",$1," in
    *,$PLATFORM,*) return 0 ;;
    *) return 1 ;;
  esac
}

manifest_skill_files() {
  local name="$1" path type _version consumers _ownership platforms relative
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_includes_project_skills "$consumers" || continue
    case "$path" in "skills/$name/"*) ;; *) continue ;; esac
    validate_platforms "$path" "$platforms"
    platform_includes_current "$platforms" || continue
    relative="${path#skills/"$name"/}"
    case "$relative" in
      ""|/*|.|..|./*|../*|*/./*|*/../*|*/.|*/..) fail "unsafe manifest skill path: $path" ;;
    esac
    printf '%s\n' "$relative"
  done < "$MANIFEST"
}

validate_skill_files() {
  local name="$1" relative files count=0
  files="$(manifest_skill_files "$name")" || fail "invalid manifest files for skill: $name"
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    count=$((count + 1))
    [ -f "$SOURCE/$name/$relative" ] || fail "manifest skill source not found: $SOURCE/$name/$relative"
  done <<< "$files"
  [ "$count" -gt 0 ] || fail "no manifest files found for skill: $name"
}

skill_is_in_sync() {
  local target="$1" name="$2" relative source_file target_file
  [ -d "$target/$name" ] || return 1
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    source_file="$SOURCE/$name/$relative"
    target_file="$target/$name/$relative"
    [ -f "$target_file" ] && cmp -s "$source_file" "$target_file" || return 1
  done < <(manifest_skill_files "$name")
  return 0
}

record_file_ownership() {
  local path="$1" proof temporary
  [ ! -L "$OWNERSHIP_FILE" ] || fail "ownership record must not be a symlink: $OWNERSHIP_FILE"
  resolve_owned_path "$path"
  proof="$(cksum "$path" | awk '{print $1 ":" $2}')"
  temporary="$(ownership_temporary)"
  awk -F '\t' -v value="$path" '$1 != value {print}' "$OWNERSHIP_FILE" > "$temporary"
  printf '%s\tfile\t%s\n' "$path" "$proof" >> "$temporary"
  mv "$temporary" "$OWNERSHIP_FILE"
}

forget_file_ownership() {
  local path="$1" temporary
  [ ! -L "$OWNERSHIP_FILE" ] || fail "ownership record must not be a symlink: $OWNERSHIP_FILE"
  resolve_owned_path "$path"
  temporary="$(ownership_temporary)"
  awk -F '\t' -v value="$path" '$1 != value {print}' "$OWNERSHIP_FILE" > "$temporary"
  mv "$temporary" "$OWNERSHIP_FILE"
}

reconcile_owned_skill_files() {
  local target="$1" target_path expected snapshot path kind proof artifact
  expected="$(mktemp)"
  snapshot="$(mktemp)"
  resolve_owned_path "$target/placeholder"
  target_path="$(dirname "$SAFE_PATH")"
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_includes_project_skills "$consumers" || continue
    platform_includes_current "$platforms" || continue
    resolve_owned_path "$target/${path#skills/}"
    printf '%s\n' "$SAFE_PATH" >> "$expected"
  done < "$MANIFEST"
  cp "$OWNERSHIP_FILE" "$snapshot"
  while IFS=$'\t' read -r path kind proof; do
    resolve_owned_path "$path"
    artifact="$SAFE_PATH"
    case "$artifact" in "$target_path"/*) ;; *) continue ;; esac
    grep -Fqx -- "$artifact" "$expected" && continue
    if [ ! -e "$artifact" ] && [ ! -L "$artifact" ]; then
      [ "$MODE" = check ] || [ "$DRY_RUN" -eq 1 ] || forget_file_ownership "$path"
      continue
    fi
    if [ "$kind" != file ] || [ ! -f "$artifact" ] || [ "$(cksum "$artifact" | awk '{print $1 ":" $2}')" != "$proof" ]; then
      printf '! preserve obsolete %s (modified or type changed)\n' "$path"
      STATUS=1
      continue
    fi
    if [ "$MODE" = check ]; then
      printf '%-24s OBSOLETE (owned)\n' "$path"
      STATUS=1
    elif [ "$DRY_RUN" -eq 1 ]; then
      printf 'would remove obsolete %s\n' "$path"
    else
      rm -f "$artifact"
      forget_file_ownership "$path"
      printf -- '- %s (obsolete)\n' "$path"
    fi
  done < "$snapshot"
  rm -f "$expected" "$snapshot"
}

copy_manifest_skill_files() {
  local target="$1" name="$2" relative source_file target_file parent
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    source_file="$SOURCE/$name/$relative"
    target_file="$target/$name/$relative"
    parent="$(dirname "$target_file")"
    mkdir -p "$parent"
    if { [ -e "$target_file" ] || [ -L "$target_file" ]; } && [ ! -f "$target_file" ]; then
      rm -rf "$target_file"
    fi
    cp "$source_file" "$target_file"
    record_file_ownership "$target_file"
  done < <(manifest_skill_files "$name")
}

check_skill() {
  local target="$1" name="$2" version="$3"
  if [ ! -e "$target/$name" ] && [ ! -L "$target/$name" ]; then
    printf '%-24s MISSING (toolkit %s)\n' "$name" "$version"
    STATUS=1
  elif skill_is_in_sync "$target" "$name"; then
    printf '%-24s in sync (%s)\n' "$name" "$version"
  else
    printf '%-24s DRIFTED (%s, manifest files)\n' "$name" "$version"
    STATUS=1
  fi
}

sync_skill() {
  local target="$1" name="$2" version="$3" action backup skill_target
  skill_target="$target/$name"
  if [ ! -e "$skill_target" ] && [ ! -L "$skill_target" ]; then
    action=add
  elif skill_is_in_sync "$target" "$name"; then
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
    backup="$(backup_path "$skill_target")"
    cp -R "$skill_target" "$backup"
    if [ ! -d "$skill_target" ]; then
      rm -rf "$skill_target"
    fi
  fi
  mkdir -p "$skill_target"
  copy_manifest_skill_files "$target" "$name"
  printf '+ %s (%s)\n' "$name" "$version"
}

main() {
  local roots target path type version name consumers _ownership platforms
  parse_arguments "$@"
  detect_platform
  PROJECT_ROOT="$(pwd -P)"
  [ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
  validate_manifest
  [ -d "$SOURCE" ] || fail "skill source not found: $SOURCE"
  [ -f "$OWNERSHIP_FILE" ] || fail "ownership record not found: $OWNERSHIP_FILE"
  validate_ownership_file
  roots="$(managed_roots)" || fail "ownership record contains unsafe skill paths"
  [ -n "$roots" ] || fail "no managed project skill roots found in $OWNERSHIP_FILE"

  while IFS= read -r target; do
    printf '%s\n' "$target"
    reconcile_owned_skill_files "$target"
    while IFS=$'\t' read -r path type version consumers _ownership platforms; do
      [ "$type" = skill ] || continue
      consumer_includes_project_skills "$consumers" || continue
      validate_platforms "$path" "$platforms"
      platform_includes_current "$platforms" || continue
      name="${path#skills/}"
      name="${name%/SKILL.md}"
      if [ -z "$name" ] || [ "${name#*/}" != "$name" ] || [ "$path" != "skills/$name/SKILL.md" ]; then
        fail "unsafe skill name in manifest: $name"
      fi
      validate_skill_files "$name"
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

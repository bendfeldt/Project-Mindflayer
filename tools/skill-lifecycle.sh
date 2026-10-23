#!/usr/bin/env bash
set -Eeuo pipefail
# Exit status 2 means "completed; migration required". Map every unexpected
# failure (for example grep or cmp reporting an error with status 2) to 1.
trap 'exit 1' ERR

MODE="${1:-}"
[ -n "$MODE" ] || { printf 'error: lifecycle mode required\n' >&2; exit 1; }
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/skill-state.sh" ] || { printf 'error: skill-state.sh not found next to %s\n' "${BASH_SOURCE[0]}" >&2; exit 1; }
# shellcheck source=tools/skill-state.sh
. "$SCRIPT_DIR/skill-state.sh"

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
ADD_REQUESTED=0
ADD_REQUEST=""
AVAILABLE=""
SELECTION=""
AGENTS_FILE=""
MIGRATIONS_FILE=""
SELECTION_INVALID=0
USE_COLOR=0
EXIT_STATUS=0

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
    if skill_record_under_replaced_dir "$path"; then continue; fi
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
    check) cat <<'USAGE'
Usage: check-skills-update.sh

Reports every skill selected in AGENTS.md as in sync, UPDATE AVAILABLE,
LOCAL CHANGES, or MISSING, and lists skills that are available but not
selected. Exits 1 when a selected skill needs attention.
USAGE
      ;;
    sync) cat <<'USAGE'
Usage: sync-skills.sh [--dry-run] [--force] [--add [SKILL[,SKILL...]]]

  --dry-run   Show what would change, including diffs, without writing
  --force     Replace files with local changes (a backup is made first)
  --add       Add skills to this project. Without names, choose from a list
              of available skills (needs a terminal).

Release updates are applied with a diff. Files with local changes are kept,
shown as a diff, and listed for migration; the exit status is then 2.
USAGE
      ;;
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
          --add)
            ADD_REQUESTED=1
            if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then
              shift
              ADD_REQUEST="${ADD_REQUEST:+$ADD_REQUEST,}$1"
            fi
            ;;
          --help|-h) usage; exit 0 ;;
          *) fail "unknown option: $1" ;;
        esac
        shift
      done
      ;;
    *) fail "unknown lifecycle mode: $MODE" ;;
  esac
}

# Skill roots come from the installer's skill-root records and, for projects
# installed before those records existed, from owned SKILL.md files.
managed_roots() {
  awk -F '\t' '
    ($2 == "directory" && $3 == "skill-root") || ($2 == "file" && $1 ~ /\/skills\/[^\/]+\/SKILL[.]md$/) {
      root=$1
      if ($2 == "file") sub(/\/[^\/]+\/SKILL[.]md$/, "", root)
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

setup_color() {
  USE_COLOR=0
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then USE_COLOR=1; fi
}

# Skills the release provides for projects on this platform, in manifest order.
available_skills() {
  local path type _version consumers _ownership platforms name result=""
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    [ "$type" = skill ] || continue
    consumer_includes_project_skills "$consumers" || continue
    platform_includes_current "$platforms" || continue
    name="${path#skills/}"; name="${name%/SKILL.md}"
    result="${result:+$result,}$name"
  done < "$MANIFEST"
  printf '%s' "$result"
}

skill_files() {
  manifest_skill_files "$1"
}

skill_version() {
  awk -F '\t' -v path="skills/$1/SKILL.md" '$1 == path {print $3; exit}' "$MANIFEST"
}

skill_description() {
  local file="$SOURCE/$1/agents/openai.yaml"
  [ -f "$file" ] || return 0
  sed -n 's/^[[:space:]]*short_description:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$file" | head -1
}

# Removes owned files that are no longer expected: files of skills that are
# not selected ("deselected") and files the release dropped ("obsolete").
# An invalid selection removes nothing as deselected, and files below a skill
# directory replaced by a link or file are never touched.
reconcile_owned_skill_files() {
  local target="$1" target_path expected declared snapshot path kind proof artifact reason name keep
  keep="$SELECTION"
  [ "$SELECTION_INVALID" -eq 0 ] || keep="$AVAILABLE"
  expected="$(mktemp)"
  declared="$(mktemp)"
  snapshot="$(mktemp)"
  resolve_owned_path "$target/placeholder"
  target_path="$(dirname "$SAFE_PATH")"
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_includes_project_skills "$consumers" || continue
    platform_includes_current "$platforms" || continue
    name="${path#skills/}"; name="${name%%/*}"
    if skill_dir_replaced "$target" "$name"; then
      SAFE_PATH="$target_path/${path#skills/}"
    else
      resolve_owned_path "$target/${path#skills/}"
    fi
    printf '%s\n' "$SAFE_PATH" >> "$declared"
    if list_contains "$name" "$keep"; then printf '%s\n' "$SAFE_PATH" >> "$expected"; fi
  done < "$MANIFEST"
  cp "$OWNERSHIP_FILE" "$snapshot"
  while IFS=$'\t' read -r path kind proof; do
    if skill_record_under_replaced_dir "$path"; then continue; fi
    resolve_owned_path "$path"
    artifact="$SAFE_PATH"
    case "$artifact" in "$target_path"/*) ;; *) continue ;; esac
    grep -Fqx -- "$artifact" "$expected" && continue
    if grep -Fqx -- "$artifact" "$declared"; then reason=deselected; else reason=obsolete; fi
    if [ ! -e "$artifact" ] && [ ! -L "$artifact" ]; then
      [ "$MODE" = check ] || [ "$DRY_RUN" -eq 1 ] || forget_file_ownership "$path"
      continue
    fi
    if [ "$kind" != file ] || [ ! -f "$artifact" ] || [ "$(fingerprint "$artifact")" != "$proof" ]; then
      if [ "$MODE" = check ]; then
        printf '%-24s LOCAL CHANGES (%s file kept; migration required)\n' "$path" "$reason"
      else
        printf '! keep %s %s (local changes)\n' "$reason" "$path"
      fi
      STATUS=1
      [ "$MODE" = check ] || record_migration kept-removal "$path" "$reason"
      continue
    fi
    if [ "$MODE" = check ]; then
      if [ "$reason" = obsolete ]; then
        printf '%-24s OBSOLETE (owned)\n' "$path"
      else
        printf '%-24s NOT SELECTED (owned; sync removes it)\n' "$path"
      fi
      STATUS=1
    elif [ "$DRY_RUN" -eq 1 ]; then
      printf 'would remove %s %s\n' "$reason" "$path"
    else
      rm -f "$artifact"
      forget_file_ownership "$path"
      printf -- '- %s (%s)\n' "$path" "$reason"
    fi
  done < "$snapshot"
  rm -f "$expected" "$declared" "$snapshot"
}

check_skill() {
  local target="$1" name="$2" version="$3" state
  state="$(skill_root_state "$target" "$name" "$SOURCE")"
  case "$state" in
    not-installed) printf '%-24s MISSING (toolkit %s)\n' "$name" "$version"; STATUS=1 ;;
    current) printf '%-24s in sync (%s)\n' "$name" "$version" ;;
    update) printf '%-24s UPDATE AVAILABLE (%s)\n' "$name" "$version"; STATUS=1 ;;
    local) printf '%-24s LOCAL CHANGES (%s; migration required)\n' "$name" "$version"; STATUS=1 ;;
    unmanaged) printf '%-24s LOCAL CHANGES (%s; not installed by the toolkit)\n' "$name" "$version"; STATUS=1 ;;
  esac
}

copy_skill_file() {
  local source_file="$1" target_file="$2"
  mkdir -p "$(dirname "$target_file")"
  if { [ -e "$target_file" ] || [ -L "$target_file" ]; } && [ ! -f "$target_file" ]; then
    rm -rf "$target_file"
  fi
  rm -f "$target_file"
  cp "$source_file" "$target_file"
  record_file_ownership "$target_file"
}

sync_skill() {
  local target="$1" name="$2" version="$3" skill_target relative source_file target_file state
  local changed=0 has_local=0 backup
  skill_target="$target/$name"
  # A skill directory replaced by a link or file is never written through: it
  # is kept as a local change, or moved aside as a whole with --force.
  if skill_dir_replaced "$target" "$name"; then
    if [ "$REPLACE" -eq 0 ]; then
      printf '! keep %s: %s (a link or file replaces the skill directory)\n' "$skill_target" "$(paint '1;31' 'LOCAL CHANGES - migration required')"
      record_migration kept "$skill_target" "$name $version"
      return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'would replace %s (not a skill directory; backup first)\n' "$skill_target"
      return
    fi
    backup="$(backup_path "$skill_target")"
    mv "$skill_target" "$backup"
    printf 'b %s\n' "$backup"
    record_migration replaced "$skill_target" "$backup"
  fi
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    state="$(file_state "$skill_target/$relative" "$SOURCE/$name/$relative")"
    case "$state" in local|unmanaged) has_local=1 ;; new|update) changed=1 ;; esac
  done < <(manifest_skill_files "$name")

  if [ "$changed" -eq 0 ] && [ "$has_local" -eq 0 ]; then
    printf '= %s\n' "$name"
    return
  fi
  [ "$DRY_RUN" -eq 1 ] || mkdir -p "$skill_target"
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    source_file="$SOURCE/$name/$relative"
    target_file="$skill_target/$relative"
    state="$(file_state "$target_file" "$source_file")"
    case "$state" in
      current) ;;
      new)
        if [ "$DRY_RUN" -eq 1 ]; then printf 'would add %s\n' "$target_file"; else copy_skill_file "$source_file" "$target_file"; printf '+ %s\n' "$target_file"; fi
        ;;
      update)
        if [ "$DRY_RUN" -eq 1 ]; then printf 'would update %s\n' "$target_file"; else printf '~ %s (update to %s %s)\n' "$target_file" "$name" "$version"; fi
        show_diff "$target_file" "$source_file" "$target_file" installed "release $version"
        [ "$DRY_RUN" -eq 1 ] || copy_skill_file "$source_file" "$target_file"
        ;;
      local|unmanaged)
        if [ "$REPLACE" -eq 1 ]; then
          if [ "$DRY_RUN" -eq 1 ]; then printf 'would replace %s (local changes; backup first)\n' "$target_file"; else printf '! replace %s (local changes; --force)\n' "$target_file"; fi
          show_diff "$target_file" "$source_file" "$target_file" "your version" "release $version"
          if [ "$DRY_RUN" -eq 0 ]; then
            # Back up the single file next to itself: a <skill>.bak directory in
            # the discovery root would be loaded by assistants as another skill.
            if [ -e "$target_file" ] || [ -L "$target_file" ]; then
              backup="$(backup_path "$target_file")"
              cp -RP "$target_file" "$backup"
              printf 'b %s\n' "$backup"
            else
              backup="(no previous file)"
            fi
            copy_skill_file "$source_file" "$target_file"
            record_migration replaced "$target_file" "$backup"
          fi
        else
          printf '! keep %s: %s\n' "$target_file" "$(paint '1;31' 'LOCAL CHANGES - migration required')"
          show_diff "$target_file" "$source_file" "$target_file" "your version" "release $version"
          record_migration kept "$target_file" "$name $version"
        fi
        ;;
    esac
  done < <(manifest_skill_files "$name")
  if [ "$DRY_RUN" -eq 0 ] && [ "$changed" -eq 1 ]; then printf '+ %s (%s)\n' "$name" "$version"; fi
}

pick_skills_to_add() {
  local candidates="$1" names=() marks=() index count input token name picked=""
  for name in ${candidates//,/ }; do names+=("$name"); marks+=(0); done
  count="${#names[@]}"
  while :; do
    {
      printf '\nAdd skills to this project\n'
      printf '         %-22s %-8s %s\n' Skill Release Description
      for index in "${!names[@]}"; do
        if [ "${marks[$index]}" -eq 1 ]; then printf '  [x] '; else printf '  [ ] '; fi
        printf '%2d %-22s %-8s %s\n' "$((index + 1))" "${names[$index]}" "$(skill_version "${names[$index]}")" "$(skill_description "${names[$index]}")"
      done
      printf '\nToggle with numbers or names (e.g. "1 3-4"), a = all, n = none,\n'
      printf 'Enter = continue, q = cancel without changes.\n> '
    } > /dev/tty
    IFS= read -r input < /dev/tty || fail "input closed; nothing was changed"
    input="$(printf '%s' "$input" | tr ',' ' ')"
    case "$input" in
      '') break ;;
      q|Q|quit|cancel) fail "cancelled; nothing was changed" ;;
      a|A|all) for index in "${!marks[@]}"; do marks[index]=1; done; continue ;;
      n|N|none) for index in "${!marks[@]}"; do marks[index]=0; done; continue ;;
    esac
    local tokens=()
    read -r -a tokens <<< "$input"
    for token in "${tokens[@]}"; do
      case "$token" in
        *[!0-9-]*|-*|*-)
          for index in "${!names[@]}"; do
            [ "${names[$index]}" != "$token" ] || { marks[index]=$((1 - marks[index])); continue 2; }
          done
          printf "Ignored '%s': not a number or skill name in the list.\n" "$token" > /dev/tty
          ;;
        *-*)
          local start="${token%%-*}" end="${token#*-}"
          case "$end" in *-*) printf "Ignored '%s': invalid range.\n" "$token" > /dev/tty; continue ;; esac
          if [ "$start" -lt 1 ] || [ "$end" -gt "$count" ] || [ "$start" -gt "$end" ]; then
            printf "Ignored '%s': choose numbers from 1 to %s.\n" "$token" "$count" > /dev/tty; continue
          fi
          for ((index = start - 1; index < end; index++)); do marks[index]=$((1 - marks[index])); done
          ;;
        *)
          if [ "$token" -lt 1 ] || [ "$token" -gt "$count" ]; then
            printf "Ignored '%s': choose numbers from 1 to %s.\n" "$token" "$count" > /dev/tty; continue
          fi
          marks[token - 1]=$((1 - marks[token - 1]))
          ;;
      esac
    done
  done
  for index in "${!names[@]}"; do
    [ "${marks[$index]}" -eq 1 ] && picked="${picked:+$picked,}${names[$index]}"
  done
  printf '%s' "$picked"
}

interactive_available() {
  [ -z "${MINDFLAYER_NONINTERACTIVE:-}" ] && [ -z "${CI:-}" ] && { : < /dev/tty; } 2>/dev/null
}

# Adds skills to the AGENTS.md selection before synchronization.
add_skills() {
  local candidates="" name requested="" token rendered proof owned=0 temporary
  if [ ! -f "$AGENTS_FILE" ] || ! grep -q '<!-- template: AGENTS ' "$AGENTS_FILE"; then
    fail "AGENTS.md is missing or not toolkit-managed; add skills with install.sh --project --skills LIST"
  fi
  [ "$SELECTION_INVALID" -eq 0 ] || fail "fix the skills line in AGENTS.md before adding skills ($SKILL_SELECTION_PROBLEM)"
  for name in ${AVAILABLE//,/ }; do
    list_contains "$name" "$SELECTION" || candidates="${candidates:+$candidates,}$name"
  done
  if [ -n "$ADD_REQUEST" ]; then
    IFS=',' read -r -a tokens <<< "$(printf '%s' "$ADD_REQUEST" | tr -d '[:space:]')"
    for token in "${tokens[@]}"; do
      [ -n "$token" ] || fail "--add contains an empty value"
      list_contains "$token" "$AVAILABLE" || fail "unknown skill '$token'; available skills: ${AVAILABLE//,/, }"
      if list_contains "$token" "$SELECTION"; then
        printf '= %s is already selected\n' "$token"
        continue
      fi
      requested="${requested:+$requested,}$token"
    done
  elif [ -z "$candidates" ]; then
    printf 'All available skills are already selected.\n'
  elif interactive_available; then
    requested="$(pick_skills_to_add "$candidates")"
  else
    fail "--add without skill names needs a terminal to choose from. Available: ${candidates//,/, }. Use --add NAME[,NAME]"
  fi
  [ -n "$requested" ] || return 0
  [ ! -L "$AGENTS_FILE" ] || fail "AGENTS.md is a symbolic link; replace it with a regular file before changing the skill selection"
  SELECTION="$(canonical_skill_csv "$SELECTION,$requested" "$AVAILABLE")"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would select skills in AGENTS.md: %s\n' "${requested//,/, }"
    return 0
  fi
  rendered="$(mktemp)"
  render_agents_selection "$AGENTS_FILE" "$rendered" "$SELECTION" "$AVAILABLE" || { rm -f "$rendered"; fail "could not update the skills line in AGENTS.md"; }
  printf '~ AGENTS.md (added: %s)\n' "${requested//,/, }"
  show_diff "$AGENTS_FILE" "$rendered" AGENTS.md current updated
  proof="$(recorded_file_proof AGENTS.md)"
  [ -z "$proof" ] || [ "$(fingerprint "$AGENTS_FILE")" != "$proof" ] || owned=1
  # Replace through a sibling temporary file so an interruption never truncates AGENTS.md.
  temporary="$(mktemp "$PROJECT_ROOT/.AGENTS.md.XXXXXX")" || fail "cannot create a temporary file next to AGENTS.md"
  cp -p "$AGENTS_FILE" "$temporary" 2>/dev/null || true
  cat "$rendered" > "$temporary"
  mv -f "$temporary" "$AGENTS_FILE"
  rm -f "$rendered"
  [ "$owned" -eq 0 ] || record_file_ownership AGENTS.md
}

main() {
  local roots target path type version name consumers _ownership platforms
  parse_arguments "$@"
  detect_platform
  setup_color
  PROJECT_ROOT="$(pwd -P)"
  AGENTS_FILE="$PROJECT_ROOT/AGENTS.md"
  [ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
  validate_manifest
  [ -d "$SOURCE" ] || fail "skill source not found: $SOURCE"
  [ -f "$OWNERSHIP_FILE" ] || fail "ownership record not found: $OWNERSHIP_FILE"
  validate_ownership_file
  roots="$(managed_roots)" || fail "ownership record contains unsafe skill paths"
  [ -n "$roots" ] || fail "no managed project skill roots found in $OWNERSHIP_FILE; install skills with install.sh --project --tools TOOL --skills LIST"
  AVAILABLE="$(available_skills)"
  read_skill_selection "$AGENTS_FILE" "$AVAILABLE"
  SELECTION="$SKILL_SELECTION"
  SELECTION_INVALID="$SKILL_SELECTION_INVALID"
  MIGRATIONS_FILE="$(mktemp)"
  trap 'rm -f "$MIGRATIONS_FILE"' EXIT
  [ "$ADD_REQUESTED" -eq 0 ] || add_skills
  if [ "$SELECTION_INVALID" -eq 1 ]; then
    if [ "$MODE" = check ]; then
      printf '%-24s INVALID SELECTION (%s; nothing is removed)\n' AGENTS.md "$SKILL_SELECTION_PROBLEM"
      STATUS=1
    else
      record_migration invalid-selection AGENTS.md "$SKILL_SELECTION_PROBLEM"
    fi
  fi

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
      if ! list_contains "$name" "$SELECTION"; then
        if [ "$MODE" = check ]; then
          printf '%-24s available (not selected)\n' "$name"
        elif [ "$DRY_RUN" -eq 0 ] && [ "$SELECTION_INVALID" -eq 0 ]; then
          remove_empty_skill_dirs "$target" "$name"
        fi
        continue
      fi
      if [ "$MODE" = check ]; then
        check_skill "$target" "$name" "$version"
      else
        sync_skill "$target" "$name" "$version"
      fi
    done < "$MANIFEST"
  done <<< "$roots"

  if [ "$MODE" = check ]; then
    if [ "$STATUS" -ne 0 ]; then
      printf '\nRun sync-skills --dry-run to see the differences, or sync-skills to apply updates.\n'
    fi
    EXIT_STATUS="$STATUS"
    return 0
  fi
  print_migration_summary || EXIT_STATUS=$?
}

main "$@"
exit "$EXIT_STATUS"

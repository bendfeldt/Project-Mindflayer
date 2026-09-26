#!/usr/bin/env bash
set -Eeuo pipefail
# Exit status 2 means "completed; migration required". Map every unexpected
# failure (for example grep or cmp reporting an error with status 2) to 1.
trap 'exit 1' ERR

VERSION="3.8.0"
KNOWN_TOOLS="claude codex gemini cursor copilot"
VALID_PROFILES="terraform databricks fabric"

INSTALL_MODE=""
SELECTED_TOOLS=""
PROFILE=""
PROJECT_TYPES=""
TECHNOLOGIES=""
PROJECT_MODE=""
CLIENT_NAME=""
CLIENT_PREFIX=""
REPLACE=0
TMP_ROOT=""
OWNERSHIP_FILE=""
OWNERSHIP_SCOPE=""
PROJECT_ROOT=""
PREFLIGHT_MANIFEST=""
BUNDLE_ROOT=""
AGENTS_TO_INSTALL=()
SKILL_ROOTS=()
PICK_NAMES=()
PICK_MARKS=()
PICKED=""
CURRENT_PLATFORM=""
SKILLS_REQUEST=""
SKILLS_REQUESTED=0
INTERACTIVE_REQUESTED=0
SKILLS_STATUS_ONLY=0
SELECTED_SKILLS=""
USE_COLOR=0
DIFFS_SHOWN=0
EXIT_STATUS=0

info() { printf '%s\n' "$*"; }
warn() { printf ' ! %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: install.sh (--global | --project) --tools TOOL[,TOOL...] [OPTIONS]

Options:
  --global          Install user-level artifacts
  --project         Install artifacts in the current repository
  --tools LIST      claude,codex,gemini,cursor,copilot
  --project-types LIST
                    infrastructure,data-platform,data-engineering (project mode)
  --technologies LIST
                    Comma-separated technology catalog identifiers (project mode)
  --profile NAME    Deprecated: terraform, databricks, or fabric (project mode)
  --client NAME     Client name (new project install)
  --prefix PREFIX   Resource prefix (new project install)
  --skills LIST     Skills to install in the project: comma-separated names,
                    "all", or "none" (project mode). Omitted: all skills for a
                    new project, the AGENTS.md selection for an existing one.
  --interactive     Choose skills from an interactive list (project mode).
                    Offered automatically when a terminal is attached.
  --skills-status   Show installed skills, available updates, and diffs, then
                    exit without changing anything (project mode)
  --force           Authorize replacement; existing files are backed up first
  --help            Show this help

Existing files are preserved unless --force explicitly authorizes replacement.
Skill updates from a newer release are applied with a diff. Skill files with
local changes are kept, shown as a diff, and listed for migration; the exit
status is then 2. Set MINDFLAYER_NONINTERACTIVE=1 or NO_COLOR=1 to disable the
interactive list or colored output.
The toolkit repository itself is not a valid --project target.

Requirements:
  Linux or macOS with Bash 3.2+, standard Unix utilities, a complete verified
  release bundle, and write access to the selected user or project paths.
  Windows 10/11 uses install.ps1 with PowerShell 7.4+; see
  docs/system-requirements.md for complete and capability-specific requirements.
USAGE
}

# shellcheck disable=SC2329 # invoked by the EXIT trap below
cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

require_value() {
  if [ $# -lt 2 ] || [ -z "$2" ] || [ "${2#--}" != "$2" ]; then
    fail "$1 requires a value"
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --global|--project)
        local requested="${1#--}"
        [ -z "$INSTALL_MODE" ] || [ "$INSTALL_MODE" = "$requested" ] || fail "--global and --project are mutually exclusive"
        INSTALL_MODE="$requested"
        ;;
      --tools) require_value "$1" "${2:-}"; shift; SELECTED_TOOLS="$1" ;;
      --profile) require_value "$1" "${2:-}"; shift; PROFILE="$1" ;;
      --project-types) require_value "$1" "${2:-}"; shift; PROJECT_TYPES="$1" ;;
      --technologies) require_value "$1" "${2:-}"; shift; TECHNOLOGIES="$1" ;;
      --client) require_value "$1" "${2:-}"; shift; CLIENT_NAME="$1" ;;
      --prefix) require_value "$1" "${2:-}"; shift; CLIENT_PREFIX="$1" ;;
      --skills) require_value "$1" "${2:-}"; shift; SKILLS_REQUEST="$1"; SKILLS_REQUESTED=1 ;;
      --interactive) INTERACTIVE_REQUESTED=1 ;;
      --skills-status) SKILLS_STATUS_ONLY=1 ;;
      --force) REPLACE=1 ;;
      --local) : ;; # Backward-compatible no-op; installation is bundle-local.
      --help|-h) usage; exit 0 ;;
      *) fail "unknown option: $1" ;;
    esac
    shift
  done
}

contains_word() {
  local needle="$1" word
  for word in $2; do [ "$word" = "$needle" ] && return 0; done
  return 1
}

validate_tools() {
  [ -n "$SELECTED_TOOLS" ] || fail "--tools is required in non-interactive operation"
  local raw tool existing
  IFS=',' read -r -a raw <<< "$SELECTED_TOOLS"
  for tool in "${raw[@]}"; do
    tool="$(printf '%s' "$tool" | tr -d '[:space:]')"
    [ -n "$tool" ] || fail "--tools contains an empty value"
    contains_word "$tool" "$KNOWN_TOOLS" || fail "unknown tool '$tool'; expected one of: ${KNOWN_TOOLS// /,}"
    for existing in "${AGENTS_TO_INSTALL[@]:-}"; do
      [ "$existing" != "$tool" ] || fail "duplicate tool '$tool'"
    done
    AGENTS_TO_INSTALL+=("$tool")
  done
}

is_selected() {
  local candidate
  for candidate in "${AGENTS_TO_INSTALL[@]}"; do [ "$candidate" = "$1" ] && return 0; done
  return 1
}

source_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

fetch_temp() {
  local path="$1"
  local source="$BUNDLE_ROOT/$path"
  [ -f "$source" ] || fail "bundle artifact not found: $path"
  printf '%s' "$source"
}

timestamp() { date '+%Y%m%d%H%M%S'; }

fingerprint() {
  cksum "$1" | awk '{print $1 ":" $2}'
}

assert_ownership_file_safe() {
  [ -n "$OWNERSHIP_FILE" ] || return 0
  [ ! -L "$OWNERSHIP_FILE" ] || fail "ownership record must not be a symlink: $OWNERSHIP_FILE"
}

canonicalize_owned_path() {
  local recorded="$1" candidate parent component suffix physical trimmed
  case "$recorded" in
    *$'\t'*|*$'\n'*|*$'\r'*|'') return 1 ;;
  esac
  case "$recorded" in
    /*) candidate="$recorded" ;;
    *) [ "$OWNERSHIP_SCOPE" = project ] || return 1; candidate="$PROJECT_ROOT/$recorded" ;;
  esac
  trimmed="${candidate#/}"
  case "/$trimmed/" in
    *'//'*) return 1 ;;
    *'/./'*|*'/../'*) return 1 ;;
  esac

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

validate_owned_path() {
  local recorded="$1" home_root
  canonicalize_owned_path "$recorded" || fail "unsafe ownership path: $recorded"
  if [ "$OWNERSHIP_SCOPE" = project ]; then
    case "$SAFE_PATH" in
      "$PROJECT_ROOT"/*) return 0 ;;
      *) fail "ownership path escapes project root: $recorded" ;;
    esac
  fi
  home_root="$(cd -P "$HOME" && pwd -P)"
  case "$SAFE_PATH" in
    "$home_root/.ai-toolkit"/*|"$home_root/.claude"/*|"$home_root/.codex"/*|\
    "$home_root/.gemini"/*|"$home_root/.cursor"/*|"$home_root/.copilot"/*|\
    "$home_root/.agents"/*) return 0 ;;
    *) fail "ownership path escapes global managed roots: $recorded" ;;
  esac
}

validate_ownership_file() {
  local path kind proof extra
  assert_ownership_file_safe
  [ -f "$OWNERSHIP_FILE" ] || return 0
  while IFS=$'\t' read -r path kind proof extra; do
    [ -n "$path" ] || fail "ownership record contains an empty path"
    [ -z "${extra:-}" ] || fail "ownership record must contain exactly three fields: $path"
    [ -n "$proof" ] || fail "ownership record contains empty evidence: $path"
    case "$kind" in file|symlink|directory|line) ;; *) fail "unknown ownership class for $path: $kind" ;; esac
    validate_owned_path "$path"
  done < "$OWNERSHIP_FILE"
}

ownership_temporary() {
  local temporary
  temporary="$(mktemp "${OWNERSHIP_FILE}.tmp.XXXXXX")" || fail "cannot create ownership temporary"
  chmod 600 "$temporary"
  printf '%s' "$temporary"
}

record_ownership() {
  local path="$1" kind="$2" proof="$3" temporary
  [ -n "$OWNERSHIP_FILE" ] || return 0
  assert_ownership_file_safe
  validate_owned_path "$path"
  mkdir -p "$(dirname "$OWNERSHIP_FILE")"
  temporary="$(ownership_temporary)"
  if [ -f "$OWNERSHIP_FILE" ]; then
    if [ "$kind" = line ]; then
      awk -F '\t' -v value="$path" -v class="$kind" -v evidence="$proof" \
        '!($1 == value && $2 == class && $3 == evidence) {print}' "$OWNERSHIP_FILE" > "$temporary"
    else
      awk -F '\t' -v value="$path" '$1 != value {print}' "$OWNERSHIP_FILE" > "$temporary"
    fi
  else
    : > "$temporary"
  fi
  printf '%s\t%s\t%s\n' "$path" "$kind" "$proof" >> "$temporary"
  mv "$temporary" "$OWNERSHIP_FILE"
}

is_recorded() {
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] && awk -F '\t' -v value="$1" '$1 == value {found=1} END {exit !found}' "$OWNERSHIP_FILE"
}

forget_ownership() {
  local path="$1" temporary
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  assert_ownership_file_safe
  validate_owned_path "$path"
  temporary="$(ownership_temporary)"
  awk -F '\t' -v value="$path" '$1 != value {print}' "$OWNERSHIP_FILE" > "$temporary"
  mv "$temporary" "$OWNERSHIP_FILE"
}

remove_verified_owned_artifact() {
  local path="$1" reason="${2:-obsolete}" record kind proof artifact
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  assert_ownership_file_safe
  validate_owned_path "$path"
  artifact="$SAFE_PATH"
  record="$(awk -F '\t' -v value="$path" '$1 == value {print $2 "\t" $3; exit}' "$OWNERSHIP_FILE")"
  [ -n "$record" ] || return 0
  IFS=$'\t' read -r kind proof <<< "$record"

  if [ ! -e "$artifact" ] && [ ! -L "$artifact" ]; then
    forget_ownership "$path"
    return 0
  fi

  case "$kind" in
    file)
      if [ ! -f "$artifact" ] || [ "$(fingerprint "$artifact")" != "$proof" ]; then
        warn "preserved $reason $path (modified or type changed)"
        record_migration kept-removal "$path" "$reason"
        return 0
      fi
      ;;
    symlink)
      if [ ! -L "$artifact" ] || [ "$(readlink "$artifact")" != "$proof" ]; then
        warn "preserved obsolete $path (target changed)"
        return 0
      fi
      ;;
    *)
      warn "preserved obsolete $path (unsupported ownership class)"
      return 0
      ;;
  esac

  rm -f "$artifact"
  forget_ownership "$path"
  info " - $path ($reason)"
}

backup_path() {
  local path="$1" backup suffix=0
  backup="${path}.bak.$(timestamp)"
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    suffix=$((suffix + 1)); backup="${path}.bak.$(timestamp).$suffix"
  done
  printf '%s' "$backup"
}

install_file() {
  local source="$1" destination="$2" label="${3:-$2}"
  if [ -n "$OWNERSHIP_FILE" ]; then validate_owned_path "$destination"; fi
  mkdir -p "$(dirname "$destination")"
  if [ -f "$destination" ] && cmp -s "$source" "$destination"; then
    info " = $label"
    if is_recorded "$destination"; then record_ownership "$destination" file "$(fingerprint "$destination")"; fi
    return 0
  fi
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ "$REPLACE" -ne 1 ]; then warn "preserved $label (use --force to replace)"; return 0; fi
    local backup; backup="$(backup_path "$destination")"
    cp -R "$destination" "$backup"
    rm -rf "$destination"
    info " b $backup"
  fi
  cp "$source" "$destination"
  record_ownership "$destination" file "$(fingerprint "$destination")"
  info " + $label"
}

install_link() {
  local target="$1" link="$2"
  if [ -n "$OWNERSHIP_FILE" ]; then validate_owned_path "$link"; fi
  mkdir -p "$(dirname "$link")"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    info " = $link"
    if is_recorded "$link"; then record_ownership "$link" symlink "$target"; fi
    return
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ "$REPLACE" -ne 1 ]; then warn "preserved $link (use --force to replace)"; return; fi
    local backup; backup="$(backup_path "$link")"
    cp -R "$link" "$backup"
    rm -rf "$link"
    info " b $backup"
  fi
  ln -s "$target" "$link"
  [ "$(readlink "$link")" = "$target" ] || fail "failed to verify symlink $link"
  record_ownership "$link" symlink "$target"
  info " + $link -> $target"
}

validate_manifest() {
  awk -F '\t' '
    function invalid_list(value, values, count, i) {
      if (value == "" || value ~ /^,/ || value ~ /,$/ || value ~ /,,/) return 1
      delete values
      delete list_seen
      count = split(value, values, ",")
      for (i = 1; i <= count; i++) {
        if (list_seen[values[i]]++) return 1
      }
      return 0
    }
    $1 !~ /^#/ && NF {
      if (NF != 6) exit 2
      if ($1 == "" || $1 ~ /^\// || $1 ~ /\\/ || $1 ~ /\/\// ||
          $1 ~ /(^|\/)\.\.?($|\/)/ || $1 ~ /\/$/) exit 2
      if (path_seen[$1]++) exit 2
      if ($2 !~ /^(baseline|decision|document|license|manifest|registry|script|setting|shim|skill|skill-resource|template)$/) exit 2
      if ($3 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 2
      if (invalid_list($4)) exit 2
      consumer_count = split($4, consumers, ",")
      for (consumer_index = 1; consumer_index <= consumer_count; consumer_index++) {
        if (consumers[consumer_index] !~ /^(global|project|project:skills|global:(claude|codex|gemini|cursor|copilot)|project:(claude|gemini)|project:claude:(terraform|databricks|fabric))$/) exit 2
      }
      if ($5 !~ /^(managed-file|managed-tree)$/) exit 2
      if (invalid_list($6)) exit 2
      platform_count = split($6, platforms, ",")
      for (platform_index = 1; platform_index <= platform_count; platform_index++) {
        if (platforms[platform_index] !~ /^(linux|macos|windows)$/) exit 2
      }
      rows++
    }
    END { if (!rows) exit 2 }
  ' "$1" || fail "manifest.tsv failed strict six-field validation"
}

manifest_rows() {
  awk -F '\t' '$1 !~ /^#/ && NF {print}' "$1"
}

validate_bundle_sources() {
  local manifest="$1" path platforms
  while IFS=$'\t' read -r path _type _version _consumers _ownership platforms; do
    platform_matches "$platforms" || continue
    [ -f "$BUNDLE_ROOT/$path" ] || fail "bundle artifact not found: $path"
  done < <(manifest_rows "$manifest")
}

detect_platform() {
  case "$(uname -s)" in
    Linux) CURRENT_PLATFORM=linux ;;
    Darwin) CURRENT_PLATFORM=macos ;;
    MINGW*|MSYS*|CYGWIN*) fail "Windows shells such as Git Bash are not supported; run install.ps1 with PowerShell 7.4+" ;;
    *) fail "unsupported platform; install.sh supports Linux and macOS" ;;
  esac
}

platform_matches() {
  local platforms="$1" item items
  IFS=',' read -r -a items <<< "$platforms"
  for item in "${items[@]}"; do [ "$item" = "$CURRENT_PLATFORM" ] && return 0; done
  return 1
}

consumer_matches() {
  local consumers="$1" wanted="$2" item
  IFS=',' read -r -a items <<< "$consumers"
  for item in "${items[@]}"; do [ "$item" = "$wanted" ] && return 0; done
  return 1
}

global_consumer_selected() {
  local consumers="$1" item tool
  IFS=',' read -r -a items <<< "$consumers"
  for item in "${items[@]}"; do
    [ "$item" = global ] && return 0
    case "$item" in
      global:*) tool="${item#global:}"; is_selected "$tool" && return 0 ;;
    esac
  done
  return 1
}

global_consumer_included() {
  local consumers="$1" item
  IFS=',' read -r -a items <<< "$consumers"
  for item in "${items[@]}"; do
    case "$item" in global|global:*) return 0 ;; esac
  done
  return 1
}

skill_names() {
  awk -F '\t' -v platform="$CURRENT_PLATFORM" '
    $2 == "skill" {
      split($6, platforms, ",")
      for (platform_index in platforms) if (platforms[platform_index] == platform) {
        sub("skills/", "", $1); sub("/SKILL.md", "", $1); print $1; break
      }
    }
  ' "$1"
}

# Removes owned files under a skill root that are no longer expected. With a
# selection (project mode), files of unselected skills are removed as
# "deselected"; files the manifest no longer declares are "obsolete".
reconcile_skill_files() {
  local manifest="$1" root="$2" selection="${3-all}" expected declared snapshot path type consumers platforms name
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  expected="$(mktemp)"
  declared="$(mktemp)"
  snapshot="$(mktemp)"
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_matches "$consumers" project:skills || continue
    platform_matches "$platforms" || continue
    printf '%s\n' "$root/${path#skills/}" >> "$declared"
    name="${path#skills/}"; name="${name%%/*}"
    if [ "$selection" = all ] || list_contains "$name" "$selection"; then
      printf '%s\n' "$root/${path#skills/}" >> "$expected"
    fi
  done < <(manifest_rows "$manifest")
  cp "$OWNERSHIP_FILE" "$snapshot"
  while IFS=$'\t' read -r path _kind _proof; do
    case "$path" in "$root"/*) ;; *) continue ;; esac
    grep -Fqx -- "$path" "$expected" && continue
    if grep -Fqx -- "$path" "$declared"; then
      remove_verified_owned_artifact "$path" deselected
    else
      remove_verified_owned_artifact "$path" obsolete
    fi
  done < "$snapshot"
  rm -f "$expected" "$declared" "$snapshot"
}

skill_root_records() {
  printf '%s\t%s\t%s\n' \
    claude global "$HOME/.claude/skills" \
    codex global "$HOME/.agents/skills" \
    copilot global "$HOME/.copilot/skills" \
    claude project '.claude/skills' \
    codex project '.agents/skills' \
    copilot project '.claude/skills'
}

selected_skill_roots() {
  local scope="$1" tool record_scope root
  while IFS=$'\t' read -r tool record_scope root; do
    [ "$record_scope" = "$scope" ] || continue
    is_selected "$tool" || continue
    printf '%s\n' "$root"
  done < <(skill_root_records) | awk '!seen[$0]++'
}

global_destination() {
  local path="$1"
  case "$path" in
    bootstrap.sh|bootstrap.ps1|install.sh|install.ps1) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    README.md|how-to-guide.md|LICENSE) printf '%s/.ai-toolkit/docs/%s' "$HOME" "$path" ;;
    global/AGENTS.md) printf '%s/.ai-toolkit/AGENTS.md' "$HOME" ;;
    CLAUDE.md|GEMINI.md) printf '%s/.ai-toolkit/templates/%s' "$HOME" "$path" ;;
    templates/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    config/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    docs/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    skills/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    tools/*) printf '%s/.ai-toolkit/%s' "$HOME" "${path#tools/}" ;;
    stores.yml|manifest.tsv) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    settings/claude/settings-terraform.json|settings/claude/settings-databricks.json|settings/claude/settings-fabric.json)
      printf '%s/.ai-toolkit/templates/settings/%s' "$HOME" "$(basename "$path")" ;;
    settings/claude/settings-global.json)
      printf '%s/.ai-toolkit/templates/settings/%s' "$HOME" "$(basename "$path")" ;;
    settings/claude/technology-permissions.tsv)
      printf '%s/.ai-toolkit/templates/settings/%s' "$HOME" "$(basename "$path")" ;;
    settings/codex/*) printf '%s/.ai-toolkit/templates/codex/%s' "$HOME" "$(basename "$path")" ;;
    settings/gemini/*) printf '%s/.ai-toolkit/templates/gemini/%s' "$HOME" "$(basename "$path")" ;;
    *) return 1 ;;
  esac
}

global_skill_roots() {
  printf '%s\n' "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.copilot/skills"
}

build_global_expected() {
  local manifest="$1" expected="$2" path consumers platforms destination root skill
  while IFS=$'\t' read -r path _type _version consumers _ownership platforms; do
    global_consumer_included "$consumers" || continue
    platform_matches "$platforms" || continue
    destination="$(global_destination "$path")" || fail "no global destination for $path"
    printf '%s\n' "$destination" >> "$expected"
  done < <(manifest_rows "$manifest")
  printf '%s\n' \
    "$HOME/.ai-toolkit/version" \
    "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" \
    "$HOME/.codex/AGENTS.md" "$HOME/.gemini/GEMINI.md" \
    "$HOME/.cursor/rules.md" "$HOME/.copilot/copilot-instructions.md" >> "$expected"
  while IFS= read -r root; do
    while IFS= read -r skill; do
      printf '%s\n' "$root/$skill" >> "$expected"
    done < <(skill_names "$manifest")
  done < <(global_skill_roots)
  awk '!seen[$0]++' "$expected" > "${expected}.unique"
  mv "${expected}.unique" "$expected"
}

reconcile_global_owned_artifacts() {
  local manifest="$1" expected snapshot path
  [ -f "$OWNERSHIP_FILE" ] || return 0
  validate_ownership_file
  expected="$(mktemp)"
  snapshot="$(mktemp)"
  build_global_expected "$manifest" "$expected"
  cp "$OWNERSHIP_FILE" "$snapshot"
  while IFS=$'\t' read -r path _kind _proof; do
    grep -Fqx -- "$path" "$expected" || remove_verified_owned_artifact "$path"
  done < "$snapshot"
  rm -f "$expected" "$snapshot"
}

install_global() {
  local manifest source path type consumers platforms destination
  manifest="$PREFLIGHT_MANIFEST"
  OWNERSHIP_SCOPE=global
  [ ! -L "$HOME/.ai-toolkit" ] || fail "global toolkit root must not be a symlink: $HOME/.ai-toolkit"
  mkdir -p "$HOME/.ai-toolkit"
  OWNERSHIP_FILE="$HOME/.ai-toolkit/managed.tsv"
  validate_ownership_file
  reconcile_global_owned_artifacts "$manifest"
  install_file "$manifest" "$HOME/.ai-toolkit/manifest.tsv" "manifest.tsv"

  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    [ "$path" = manifest.tsv ] && continue
    global_consumer_selected "$consumers" || continue
    platform_matches "$platforms" && continue
    destination="$(global_destination "$path")" || fail "no global destination for $path"
    remove_verified_owned_artifact "$destination"
  done < <(manifest_rows "$manifest")
  reconcile_skill_files "$manifest" "$HOME/.ai-toolkit/skills"

  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    [ "$path" = manifest.tsv ] && continue
    global_consumer_selected "$consumers" || continue
    platform_matches "$platforms" || continue
    source="$(fetch_temp "$path")"
    destination="$(global_destination "$path")" || fail "no global destination for $path"
    install_file "$source" "$destination"
    [ "$type" != script ] || chmod +x "$destination"
  done < <(manifest_rows "$manifest")

  local baseline="$HOME/.ai-toolkit/AGENTS.md" agent skill skill_root
  for agent in "${AGENTS_TO_INSTALL[@]}"; do
    case "$agent" in
      claude)
        install_file "$baseline" "$HOME/.claude/CLAUDE.md"
        source="$(fetch_temp settings/claude/settings-global.json)"
        install_file "$source" "$HOME/.claude/settings.json"
        ;;
      codex) install_file "$baseline" "$HOME/.codex/AGENTS.md" ;;
      gemini) install_file "$baseline" "$HOME/.gemini/GEMINI.md" ;;
      cursor) install_file "$baseline" "$HOME/.cursor/rules.md" ;;
      copilot) install_file "$baseline" "$HOME/.copilot/copilot-instructions.md" ;;
    esac
  done

  while IFS= read -r skill_root; do
    while IFS= read -r skill; do
      install_link "$HOME/.ai-toolkit/skills/$skill" "$skill_root/$skill"
    done < <(skill_names "$manifest")
  done < <(selected_skill_roots global)

  # Commit the release stamp only after every requested artifact succeeds.
  printf '%s\n' "$VERSION" > "$HOME/.ai-toolkit/version.tmp"
  mv "$HOME/.ai-toolkit/version.tmp" "$HOME/.ai-toolkit/version"
  record_ownership "$HOME/.ai-toolkit/version" file "$(fingerprint "$HOME/.ai-toolkit/version")"
  info "Installed toolkit $VERSION for: ${AGENTS_TO_INSTALL[*]}"
}

validate_profile() {
  contains_word "$PROFILE" "$VALID_PROFILES" || fail "invalid profile '$PROFILE'; expected: ${VALID_PROFILES// /,}"
}

catalog_values() {
  local catalog="$1" group="$2"
  awk -F '\t' -v group="$group" '
    $1 !~ /^#/ && ((group == "project-type" && $2 == group) || (group == "technology" && $2 != "project-type")) {
      printf "%s%s", separator, $1
      separator = ","
    }
    END { print "" }
  ' "$catalog"
}

canonicalize_catalog_list() {
  local raw_list="$1" group="$2" flag="$3" catalog="$4"
  local token canonical selected_file supported
  local raw_values=()
  selected_file="${catalog}.selected-${group}"
  : > "$selected_file"
  IFS=',' read -r -a raw_values <<< "$raw_list"
  for token in "${raw_values[@]}"; do
    token="$(printf '%s' "$token" | tr -d '[:space:]')"
    [ -n "$token" ] || fail "$flag contains an empty value"
    [ "$token" = "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')" ] || fail "$flag value '$token' must be lowercase"
    canonical="$(awk -F '\t' -v value="$token" -v group="$group" '
      $1 !~ /^#/ && ((group == "project-type" && $2 == group) || (group == "technology" && $2 != "project-type")) {
        if ($1 == value) { print $1; exit }
        count = split($4, aliases, ",")
        for (position = 1; position <= count; position++) {
          if (aliases[position] != "-" && aliases[position] == value) { print $1; exit }
        }
      }
    ' "$catalog")"
    if [ -z "$canonical" ]; then
      supported="$(catalog_values "$catalog" "$group")"
      fail "unknown $flag value '$token'; expected one of: $supported"
    fi
    ! grep -Fqx -- "$canonical" "$selected_file" || fail "duplicate $flag value '$canonical'"
    printf '%s\n' "$canonical" >> "$selected_file"
  done
  awk -F '\t' -v selected_file="$selected_file" '
    BEGIN {
      while ((getline selected < selected_file) > 0) wanted[selected] = 1
      close(selected_file)
    }
    $1 !~ /^#/ && ($1 in wanted) {
      printf "%s%s", separator, $1
      separator = ","
    }
    END { print "" }
  ' "$catalog"
  rm -f "$selected_file"
}

compose_claude_settings() {
  local policy="$1" destination="$2"
  awk -F '\t' -v technologies="$TECHNOLOGIES" '
    function json_escape(value) {
      gsub(/\\/, "\\\\", value)
      gsub(/\"/, "\\\"", value)
      return value
    }
    BEGIN {
      row_count = 0
      count = split(technologies, values, ",")
      for (position = 1; position <= count; position++) selected[values[position]] = 1
    }
    $1 !~ /^#/ && ($1 in selected) && ($2 == "allow" || $2 == "deny") {
      effect[row_count] = $2
      pattern[row_count] = $3
      if ($2 == "deny") denied[$3] = 1
      row_count++
    }
    END {
      print "{"
      print "  \"permissions\": {"
      print "    \"allow\": ["
      separator = ""
      for (position = 0; position < row_count; position++) {
        key = effect[position] SUBSEP pattern[position]
        if (effect[position] == "allow" && !(pattern[position] in denied) && !(key in emitted)) {
          printf "%s      \"%s\"", separator, json_escape(pattern[position])
          separator = ",\n"
          emitted[key] = 1
        }
      }
      if (separator != "") print ""
      print "    ],"
      print "    \"deny\": ["
      separator = ""
      for (position = 0; position < row_count; position++) {
        key = effect[position] SUBSEP pattern[position]
        if (effect[position] == "deny" && !(key in emitted)) {
          printf "%s      \"%s\"", separator, json_escape(pattern[position])
          separator = ",\n"
          emitted[key] = 1
        }
      }
      if (separator != "") print ""
      print "    ]"
      print "  }"
      print "}"
    }
  ' "$policy" > "$destination"
}

replace_tokens() {
  local source="$1" destination="$2" repo_type safe_client safe_prefix
  case "$PROFILE" in terraform) repo_type="infrastructure" ;; *) repo_type="data-platform" ;; esac
  safe_client="$(printf '%s' "$CLIENT_NAME" | sed 's/[&|\\]/\\&/g')"
  safe_prefix="$(printf '%s' "$CLIENT_PREFIX" | sed 's/[&|\\]/\\&/g')"
  sed -e "s|{CLIENT_NAME}|$safe_client|g" -e "s|{PLATFORM}|$PROFILE|g" -e "s|{REPO_TYPE}|$repo_type|g" -e "s|{prefix}|$safe_prefix|g" "$source" > "$destination"
}

replace_composable_tokens() {
  local source="$1" destination="$2" safe_client safe_prefix resource_line
  safe_client="$(printf '%s' "$CLIENT_NAME" | sed 's/[&|\\]/\\&/g')"
  resource_line=""
  if [ -n "$CLIENT_PREFIX" ]; then
    safe_prefix="$(printf '%s' "$CLIENT_PREFIX" | sed 's/[&|\\]/\\&/g')"
    resource_line="- **resource prefix:** \`$safe_prefix\`"
  fi
  sed \
    -e "s|{CLIENT_NAME}|$safe_client|g" \
    -e "s|{PROJECT_TYPES}|${PROJECT_TYPES//,/, }|g" \
    -e "s|{TECHNOLOGIES}|${TECHNOLOGIES//,/, }|g" \
    -e "s|{RESOURCE_PREFIX_LINE}|$resource_line|g" \
    "$source" > "$destination"
}

append_gitignore_exact() {
  local entry="$1"
  touch .gitignore
  if ! grep -Fqx -- "$entry" .gitignore; then
    printf '%s\n' "$entry" >> .gitignore
    record_ownership "$(pwd)/.gitignore" line "$entry"
  fi
}

migrate_legacy_project_artifacts() {
  local consumer="$1" path
  case "$consumer" in
    claude)
      for path in \
        .claude/rules/README.md \
        .claude/commands/README.md \
        .claude/agents/README.md \
        .claude/hooks/README.md; do
        remove_verified_owned_artifact "$path"
      done
      rmdir .claude/rules .claude/commands .claude/agents .claude/hooks 2>/dev/null || true
      ;;
    codex) remove_verified_owned_artifact codex.md ;;
    gemini) remove_verified_owned_artifact gemini.md ;;
    cursor) remove_verified_owned_artifact .cursor/rules/project.md ;;
    copilot) remove_verified_owned_artifact .github/copilot-instructions.md ;;
  esac
}

# ---------------------------------------------------------------------------
# Project skill selection, status detection, diffs, and migration reporting.
# ---------------------------------------------------------------------------

list_contains() {
  case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

setup_color() {
  USE_COLOR=0
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then USE_COLOR=1; fi
}

paint() {
  if [ "$USE_COLOR" -eq 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

tty_paint() {
  if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

interactive_available() {
  [ -z "${MINDFLAYER_NONINTERACTIVE:-}" ] && [ -z "${CI:-}" ] && [ -t 1 ] && { : < /dev/tty; } 2>/dev/null
}

# TMP_ROOT is created in main, never inside a command substitution, so every
# helper shares one working directory that the EXIT trap removes.
skill_work_dir() {
  [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] || fail "internal error: working directory not initialized"
  printf '%s' "$TMP_ROOT"
}

# Cache project skill metadata: skills.tsv (name, version, description) and
# skill-files.tsv (name, relative path) in manifest order.
load_skill_catalog() {
  local work path type version consumers platforms name description
  work="$(skill_work_dir)"
  [ ! -f "$work/skills.tsv" ] || return 0
  : > "$work/skills.tsv"
  : > "$work/skill-files.tsv"
  while IFS=$'\t' read -r path type version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_matches "$consumers" project:skills || continue
    platform_matches "$platforms" || continue
    name="${path#skills/}"; name="${name%%/*}"
    case "$name" in ''|*[!a-z0-9-]*) fail "unsafe skill name in manifest: $path" ;; esac
    printf '%s\t%s\n' "$name" "${path#skills/"$name"/}" >> "$work/skill-files.tsv"
    if [ "$type" = skill ]; then
      description=""
      if [ -f "$BUNDLE_ROOT/skills/$name/agents/openai.yaml" ]; then
        description="$(sed -n 's/^[[:space:]]*short_description:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$BUNDLE_ROOT/skills/$name/agents/openai.yaml" | head -1)"
      fi
      printf '%s\t%s\t%s\n' "$name" "$version" "$description" >> "$work/skills.tsv"
    fi
  done < <(manifest_rows "$PREFLIGHT_MANIFEST")
  [ -s "$work/skills.tsv" ] || fail "the release bundle declares no project skills"
}

skill_names_list() { awk -F '\t' '{print $1}' "$(skill_work_dir)/skills.tsv"; }
skill_version() { awk -F '\t' -v name="$1" '$1 == name {print $2; exit}' "$(skill_work_dir)/skills.tsv"; }
skill_files() { awk -F '\t' -v name="$1" '$1 == name {print $2}' "$(skill_work_dir)/skill-files.tsv"; }
all_skills_csv() { skill_names_list | paste -sd, -; }

# Put a comma-separated selection into manifest order.
canonical_skill_csv() {
  local wanted="$1" name result=""
  while IFS= read -r name; do
    list_contains "$name" "$wanted" || continue
    result="${result:+$result,}$name"
  done < <(skill_names_list)
  printf '%s' "$result"
}

parse_skill_request() {
  local request="$1" token seen="" available
  available="$(all_skills_csv)"
  request="$(printf '%s' "$request" | tr -d '[:space:]')"
  case "$request" in
    all) printf '%s' "$available"; return 0 ;;
    none) return 0 ;;
    '') fail "--skills requires a value: skill names, all, or none" ;;
  esac
  IFS=',' read -r -a tokens <<< "$request"
  for token in "${tokens[@]}"; do
    [ -n "$token" ] || fail "--skills contains an empty value"
    case "$token" in all|none) fail "--skills: '$token' cannot be combined with skill names" ;; esac
    list_contains "$token" "$available" || fail "unknown skill '$token'; available skills: ${available//,/, }"
    ! list_contains "$token" "$seen" || fail "duplicate skill '$token' in --skills"
    seen="${seen:+$seen,}$token"
  done
  canonical_skill_csv "$seen"
}

agents_has_skills_line() {
  [ -f "$1" ] && grep -Eq '^[[:space:]]*- \*\*skills:\*\*' "$1"
}

# Reads the stored selection. Unknown names (for example a skill retired by a
# newer release) are reported and ignored.
stored_skill_selection() {
  local agents="$1" raw token kept="" available
  available="$(all_skills_csv)"
  raw="$(sed -n 's/^[[:space:]]*- \*\*skills:\*\*[[:space:]]*//p' "$agents" | head -1 | tr -d '[:space:]')"
  [ "$raw" != none ] && [ -n "$raw" ] || return 0
  IFS=',' read -r -a tokens <<< "$raw"
  for token in "${tokens[@]}"; do
    [ -n "$token" ] || continue
    if list_contains "$token" "$available"; then
      kept="${kept:+$kept,}$token"
    else
      warn "AGENTS.md selects skill '$token', which this release does not provide; ignoring it" >&2
    fi
  done
  canonical_skill_csv "$kept"
}

skills_line_value() {
  if [ -z "$1" ]; then printf 'none'; else printf '%s' "${1//,/, }"; fi
}

# Writes AGENTS.md content with the skills line set (or removed when every
# skill is selected, so default projects keep the unchanged template).
render_agents_selection() {
  local source="$1" destination="$2" selection="$3" mode=set line
  if [ "$selection" = "$(all_skills_csv)" ]; then mode=remove; fi
  line="- **skills:** $(skills_line_value "$selection")"
  awk -v mode="$mode" -v line="$line" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (lines[i] ~ /^[[:space:]]*- \*\*skills:\*\*/) { existing = i; break }
      if (!existing && mode == "set") {
        for (i = 1; i <= NR; i++) {
          if (lines[i] ~ /^##[[:space:]]+Repository identity[[:space:]]*$/) { in_identity = 1; continue }
          if (in_identity && lines[i] ~ /^## /) break
          if (in_identity && lines[i] ~ /^- \*\*[^*]+:\*\*/) anchor = i
        }
        if (!anchor) for (i = 1; i <= NR; i++) if (lines[i] ~ /<!-- template: AGENTS /) { anchor = i; break }
        if (!anchor) exit 3
      }
      for (i = 1; i <= NR; i++) {
        if (i == existing) { if (mode == "set") print line; continue }
        print lines[i]
        if (i == anchor) print line
      }
    }
  ' "$source" > "$destination"
}

recorded_file_proof() {
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  awk -F '\t' -v value="$1" '$1 == value && $2 == "file" {print $3; exit}' "$OWNERSHIP_FILE"
}

# State of one manifest file in a skill root:
#   new       missing locally
#   current   identical to the release
#   update    unchanged since the toolkit installed it; the release differs
#   local     installed by the toolkit, then edited
#   unmanaged exists but was not installed by the toolkit
file_state() {
  local destination="$1" source="$2" proof
  if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then printf 'new'; return; fi
  proof="$(recorded_file_proof "$destination")"
  if [ -L "$destination" ] || [ ! -f "$destination" ]; then
    if [ -n "$proof" ]; then printf 'local'; else printf 'unmanaged'; fi
    return
  fi
  if cmp -s "$source" "$destination"; then printf 'current'; return; fi
  if [ -z "$proof" ]; then printf 'unmanaged'
  elif [ "$(fingerprint "$destination")" = "$proof" ]; then printf 'update'
  else printf 'local'; fi
}

state_rank() {
  case "$1" in not-installed) printf 0 ;; current) printf 1 ;; update) printf 2 ;; local) printf 3 ;; unmanaged) printf 4 ;; esac
}

# Aggregated state of a skill in one root, including owned files the release
# no longer declares.
skill_root_state() {
  local root="$1" name="$2" relative state worst=current existing=0 path proof
  if [ ! -e "$root/$name" ] && [ ! -L "$root/$name" ]; then printf 'not-installed'; return; fi
  while IFS= read -r relative; do
    state="$(file_state "$root/$name/$relative" "$BUNDLE_ROOT/skills/$name/$relative")"
    if [ "$state" = new ]; then state=update; else existing=1; fi
    [ "$(state_rank "$state")" -le "$(state_rank "$worst")" ] || worst="$state"
  done < <(skill_files "$name")
  if [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ]; then
    while IFS=$'\t' read -r path proof; do
      skill_files "$name" | grep -Fqx -- "${path#"$root/$name/"}" && continue
      [ -e "$path" ] || continue
      existing=1
      if [ -f "$path" ] && [ ! -L "$path" ] && [ "$(fingerprint "$path")" = "$proof" ]; then state=update; else state=local; fi
      [ "$(state_rank "$state")" -le "$(state_rank "$worst")" ] || worst="$state"
    done < <(awk -F '\t' -v prefix="$root/$name/" '$2 == "file" && index($1, prefix) == 1 {print $1 "\t" $3}' "$OWNERSHIP_FILE")
  fi
  if [ "$existing" -eq 0 ] && [ "$worst" = update ]; then
    # The directory exists but holds none of the skill's files.
    if [ -n "$(find "$root/$name" -mindepth 1 -print -quit 2>/dev/null)" ]; then printf 'unmanaged'; else printf 'not-installed'; fi
    return
  fi
  printf '%s' "$worst"
}

# Writes states.tsv: name, aggregated state across the selected roots, and
# whether the toolkit owns the skill in any root.
compute_skill_states() {
  local work name state worst root owned missing
  work="$(skill_work_dir)"
  : > "$work/states.tsv"
  while IFS= read -r name; do
    worst=""
    missing=0
    owned=no
    for root in "${SKILL_ROOTS[@]}"; do
      state="$(skill_root_state "$root" "$name")"
      if [ "$state" = not-installed ]; then
        missing=1
      elif [ -z "$worst" ] || [ "$(state_rank "$state")" -gt "$(state_rank "$worst")" ]; then
        worst="$state"
      fi
      if [ -n "$(recorded_file_proof "$root/$name/SKILL.md")" ]; then owned=yes; fi
    done
    if [ -z "$worst" ]; then
      worst=not-installed
    elif [ "$missing" -eq 1 ] && [ "$worst" = current ]; then
      # Installed in some roots only: adding it to the others is an update.
      worst=update
    fi
    printf '%s\t%s\t%s\n' "$name" "$worst" "$owned" >> "$work/states.tsv"
  done < <(skill_names_list)
}

skill_state() { awk -F '\t' -v name="$1" '$1 == name {print $2; exit}' "$(skill_work_dir)/states.tsv"; }

state_label() {
  case "$1" in
    not-installed) printf 'not installed' ;;
    current) printf 'up to date' ;;
    update) printf 'update available' ;;
    local) printf 'local changes' ;;
    unmanaged) printf 'not managed' ;;
  esac
}

state_color() {
  case "$1" in current) printf '32' ;; update) printf '33' ;; local|unmanaged) printf '31' ;; *) printf '2' ;; esac
}

colorize_diff() {
  if [ "$USE_COLOR" -eq 1 ]; then
    awk '
      /^(---|\+\+\+) / { printf "\033[1m%s\033[0m\n", $0; next }
      /^@@/ { printf "\033[36m%s\033[0m\n", $0; next }
      /^-/ { printf "\033[31m%s\033[0m\n", $0; next }
      /^\+/ { printf "\033[32m%s\033[0m\n", $0; next }
      { print }
    '
  else
    cat
  fi
}

# Unified diff from the local file (---) to the release (+++).
show_diff() {
  local local_file="$1" release_file="$2" label="$3" local_description="$4" release_description="$5"
  [ -f "$local_file" ] && [ ! -L "$local_file" ] || local_file=/dev/null
  { diff -u -L "$label ($local_description)" -L "$label ($release_description)" "$local_file" "$release_file" || true; } | colorize_diff
}

record_migration() {
  [ "$OWNERSHIP_SCOPE" = project ] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$(skill_work_dir)/migrations.tsv"
}

# Prints the diffs for every changed file of the given skills in all roots.
print_skill_diffs() {
  local names="$1" name root relative destination state version
  for name in ${names//,/ }; do
    version="$(skill_version "$name")"
    for root in "${SKILL_ROOTS[@]}"; do
      while IFS= read -r relative; do
        destination="$root/$name/$relative"
        state="$(file_state "$destination" "$BUNDLE_ROOT/skills/$name/$relative")"
        case "$state" in
          update) show_diff "$destination" "$BUNDLE_ROOT/skills/$name/$relative" "$destination" installed "release $version" ;;
          local|unmanaged)
            info "$(paint '1;31' "LOCAL CHANGES - migration required:") $destination"
            show_diff "$destination" "$BUNDLE_ROOT/skills/$name/$relative" "$destination" "your version" "release $version"
            ;;
        esac
      done < <(skill_files "$name")
    done
  done
}

draw_picker() {
  local title="$1" index name version description state mark
  {
    printf '\n%s\n' "$(tty_paint 1 "$title")"
    printf '         %-22s %-17s %-8s %s\n' Skill Status Release Description
    for index in "${!PICK_NAMES[@]}"; do
      name="${PICK_NAMES[$index]}"
      state="$(skill_state "$name")"
      version="$(skill_version "$name")"
      description="$(awk -F '\t' -v name="$name" '$1 == name {print $3; exit}' "$(skill_work_dir)/skills.tsv")"
      if [ "${PICK_MARKS[$index]}" -eq 1 ]; then mark='[x]'; else mark='[ ]'; fi
      printf '  %s %2d %-22s %s %-8s %s\n' "$mark" "$((index + 1))" "$name" \
        "$(tty_paint "$(state_color "$state")" "$(printf '%-17s' "$(state_label "$state")")")" "$version" "$description"
    done
    printf '\nToggle with numbers or names (e.g. "3 5-7"), a = all, n = none,\n'
    printf 'Enter = continue, q = cancel without changes.\n'
  } > /dev/tty
}

# Interactive multi-select. Sets PICKED to a manifest-ordered comma list.
run_picker() {
  local title="$1" candidates="$2" preselected="$3" input token start end index name matched count
  local tokens=()
  PICK_NAMES=()
  PICK_MARKS=()
  for name in ${candidates//,/ }; do
    PICK_NAMES+=("$name")
    if list_contains "$name" "$preselected"; then PICK_MARKS+=(1); else PICK_MARKS+=(0); fi
  done
  count="${#PICK_NAMES[@]}"
  [ "$count" -gt 0 ] || { PICKED=""; return 0; }
  while :; do
    draw_picker "$title"
    printf '> ' > /dev/tty
    IFS= read -r input < /dev/tty || fail "input closed; nothing was changed"
    input="$(printf '%s' "$input" | tr ',' ' ')"
    case "$input" in
      '') break ;;
      q|Q|quit|cancel) fail "cancelled; nothing was changed" ;;
      a|A|all) for index in "${!PICK_MARKS[@]}"; do PICK_MARKS[index]=1; done; continue ;;
      n|N|none) for index in "${!PICK_MARKS[@]}"; do PICK_MARKS[index]=0; done; continue ;;
    esac
    read -r -a tokens <<< "$input"
    for token in "${tokens[@]}"; do
      case "$token" in
        *[!0-9-]*|-*|*-)
          matched=0
          for index in "${!PICK_NAMES[@]}"; do
            if [ "${PICK_NAMES[$index]}" = "$token" ]; then PICK_MARKS[index]=$((1 - PICK_MARKS[index])); matched=1; fi
          done
          [ "$matched" -eq 1 ] || printf '%s\n' "$(tty_paint 33 "Ignored '$token': not a number or skill name in the list.")" > /dev/tty
          ;;
        *-*)
          start="${token%%-*}"; end="${token#*-}"
          case "$end" in *-*) printf "Ignored '%s': invalid range.\n" "$token" > /dev/tty; continue ;; esac
          if [ "$start" -lt 1 ] || [ "$end" -gt "$count" ] || [ "$start" -gt "$end" ]; then
            printf '%s\n' "$(tty_paint 33 "Ignored '$token': choose numbers from 1 to $count.")" > /dev/tty
            continue
          fi
          for ((index = start - 1; index < end; index++)); do PICK_MARKS[index]=$((1 - PICK_MARKS[index])); done
          ;;
        *)
          if [ "$token" -lt 1 ] || [ "$token" -gt "$count" ]; then
            printf '%s\n' "$(tty_paint 33 "Ignored '$token': choose numbers from 1 to $count.")" > /dev/tty
            continue
          fi
          PICK_MARKS[token - 1]=$((1 - PICK_MARKS[token - 1]))
          ;;
      esac
    done
  done
  PICKED=""
  for index in "${!PICK_NAMES[@]}"; do
    [ "${PICK_MARKS[$index]}" -eq 1 ] || continue
    PICKED="${PICKED:+$PICKED,}${PICK_NAMES[$index]}"
  done
}

# Summarizes planned skill changes. Returns 1 when nothing would change.
print_skill_plan() {
  local selection="$1" name state owned changes=0 line
  while IFS=$'\t' read -r name state owned; do
    line=""
    if list_contains "$name" "$selection"; then
      case "$state" in
        not-installed) line="$(paint 32 '+ install ')  $name $(skill_version "$name")" ;;
        update) line="$(paint 33 '~ update  ')  $name -> $(skill_version "$name")" ;;
        local|unmanaged)
          if [ "$REPLACE" -eq 1 ]; then
            line="$(paint 31 '! replace ')  $name ($(state_label "$state"); your version is backed up first)"
          else
            line="$(paint 31 '! keep    ')  $name ($(state_label "$state"); migration required, --force replaces)"
          fi
          ;;
      esac
    else
      case "$state" in
        not-installed) ;;
        unmanaged) line="$(paint 2 '= leave   ')  $name (not installed by the toolkit)" ;;
        local) line="$(paint 31 '- remove  ')  $name (unchanged files only; edited files are kept)" ;;
        *) [ "$owned" = yes ] && line="$(paint 31 '- remove  ')  $name" ;;
      esac
    fi
    [ -n "$line" ] || continue
    [ "$changes" -gt 0 ] || info "Planned skill changes:"
    info "  $line"
    changes=$((changes + 1))
  done < "$(skill_work_dir)/states.tsv"
  [ "$changes" -gt 0 ]
}

confirm_skill_plan() {
  local selection="$1" answer changed_names="" name state _owned
  while IFS=$'\t' read -r name state _owned; do
    list_contains "$name" "$selection" || continue
    case "$state" in update|local|unmanaged) changed_names="${changed_names:+$changed_names,}$name" ;; esac
  done < "$(skill_work_dir)/states.tsv"
  while :; do
    if [ -n "$changed_names" ]; then
      printf 'Proceed? [Y]es, [n]o, [d]iffs: ' > /dev/tty
    else
      printf 'Proceed? [Y]es, [n]o: ' > /dev/tty
    fi
    IFS= read -r answer < /dev/tty || fail "input closed; nothing was changed"
    case "$answer" in
      ''|y|Y|yes) return 0 ;;
      n|N|no|q|Q) fail "cancelled; nothing was changed" ;;
      d|D)
        if [ -n "$changed_names" ]; then print_skill_diffs "$changed_names"; DIFFS_SHOWN=1; fi
        ;;
    esac
  done
}

# Installs or updates one manifest file of a selected skill, showing a diff
# for every change and recording local changes for migration.
install_skill_file() {
  local name="$1" relative="$2" root="$3" source destination state version backup
  source="$(fetch_temp "skills/$name/$relative")"
  destination="$root/$name/$relative"
  version="$(skill_version "$name")"
  validate_owned_path "$destination"
  state="$(file_state "$destination" "$source")"
  case "$state" in
    new|current) install_file "$source" "$destination" ;;
    update)
      info " ~ $destination (update to $name $version)"
      [ "$DIFFS_SHOWN" -eq 1 ] || show_diff "$destination" "$source" "$destination" installed "release $version"
      rm -f "$destination"
      cp "$source" "$destination"
      record_ownership "$destination" file "$(fingerprint "$destination")"
      ;;
    local|unmanaged)
      if [ "$REPLACE" -eq 1 ]; then
        warn "$destination has local changes; replacing it with $name $version (--force)"
        [ "$DIFFS_SHOWN" -eq 1 ] || show_diff "$destination" "$source" "$destination" "your version" "release $version"
        backup="$(backup_path "$destination")"
        cp -R "$destination" "$backup"
        rm -rf "$destination"
        info " b $backup"
        mkdir -p "$(dirname "$destination")"
        cp "$source" "$destination"
        record_ownership "$destination" file "$(fingerprint "$destination")"
        record_migration replaced "$destination" "$backup"
      else
        warn "$destination has local changes; kept. $(paint '1;31' 'LOCAL CHANGES - migration required')"
        [ "$DIFFS_SHOWN" -eq 1 ] || show_diff "$destination" "$source" "$destination" "your version" "release $version"
        record_migration kept "$destination" "$name $version"
      fi
      ;;
  esac
}

remove_empty_skill_dirs() {
  local root="$1" name="$2" relative directory
  while IFS= read -r relative; do
    directory="$(dirname "$root/$name/$relative")"
    while [ "$directory" != "$root" ] && [ "$directory" != "$root/$name/." ]; do
      rmdir "$directory" 2>/dev/null || break
      directory="$(dirname "$directory")"
    done
  done < <(skill_files "$name")
}

print_migration_summary() {
  local file work kept=0 replaced=0 removal=0 kind path detail
  work="$(skill_work_dir)"
  file="$work/migrations.tsv"
  [ -s "$file" ] || return 0
  kept="$(awk -F '\t' '$1 == "kept" {n++} END {print n + 0}' "$file")"
  replaced="$(awk -F '\t' '$1 == "replaced" {n++} END {print n + 0}' "$file")"
  removal="$(awk -F '\t' '$1 == "kept-removal" {n++} END {print n + 0}' "$file")"
  info ""
  info "$(paint '1;31' 'Migration required')"
  if [ "$kept" -gt 0 ]; then
    info "  Kept with local changes, not updated ($kept):"
    while IFS=$'\t' read -r kind path detail; do
      [ "$kind" = kept ] && info "    ! $path  (release: $detail)"
    done < "$file"
  fi
  if [ "$removal" -gt 0 ]; then
    info "  Kept although no longer installed, because they have local changes ($removal):"
    while IFS=$'\t' read -r kind path detail; do
      [ "$kind" = kept-removal ] && info "    ! $path  ($detail)"
    done < "$file"
  fi
  if [ "$replaced" -gt 0 ]; then
    info "  Replaced by the release; your previous version was saved ($replaced):"
    while IFS=$'\t' read -r kind path detail; do
      [ "$kind" = replaced ] && info "    ! $path  -> $detail"
    done < "$file"
  fi
  info "  Next steps:"
  if [ "$kept" -gt 0 ]; then
    info "    - Review the diffs above: '-' lines are your version, '+' lines are the release."
    info "      Move your customizations out of toolkit-managed files (for example into a"
    info "      project-specific skill), then rerun with --force to take the release."
    info "      --force saves your version as <file>.bak.<timestamp> before replacing it."
  fi
  if [ "$removal" -gt 0 ]; then
    info "    - Files kept after their skill was removed stay listed here until you delete them."
    info "      Copy anything you still need into your own files, then delete them."
  fi
  if [ "$replaced" -gt 0 ]; then
    info "    - Re-apply any customizations you still need from the saved .bak files."
  fi
  if [ "$kept" -gt 0 ] || [ "$removal" -gt 0 ]; then EXIT_STATUS=2; fi
}

join_roots() {
  local root joined=""
  for root in "${SKILL_ROOTS[@]}"; do joined="${joined:+$joined, }$root"; done
  printf '%s' "$joined"
}

# Shows the selection, per-root status, and diffs without changing anything.
print_skills_status() {
  local agents=AGENTS.md selection name state _owned version root root_state marker
  load_skill_catalog
  compute_skill_states
  if [ -f "$agents" ] && agents_has_skills_line "$agents"; then
    selection="$(stored_skill_selection "$agents")"
    info "Selected in AGENTS.md: $(skills_line_value "$selection")"
  else
    selection="$(all_skills_csv)"
    if [ -f "$agents" ]; then info "Selected in AGENTS.md: all skills (no skills line)"; else info "No AGENTS.md yet: a new install selects all skills"; fi
  fi
  for root in "${SKILL_ROOTS[@]}"; do
    info ""
    info "$(paint 1 "$root")"
    info "$(printf '      %-22s %-17s %s' Skill Status Release)"
    while IFS= read -r name; do
      root_state="$(skill_root_state "$root" "$name")"
      version="$(skill_version "$name")"
      if list_contains "$name" "$selection"; then marker='[x]'; else marker='[ ]'; fi
      info "  $marker $(printf '%-22s' "$name") $(paint "$(state_color "$root_state")" "$(printf '%-17s' "$(state_label "$root_state")")") $version"
    done < <(skill_names_list)
  done
  local changed=""
  while IFS=$'\t' read -r name state _owned; do
    case "$state" in update|local|unmanaged) changed="${changed:+$changed,}$name" ;; esac
  done < "$(skill_work_dir)/states.tsv"
  info ""
  if [ -n "$changed" ]; then
    info "$(paint 1 'Differences (--- installed, +++ release):')"
    print_skill_diffs "$changed"
    info ""
    info "Apply release updates by rerunning without --skills-status. Files with local"
    info "changes are kept and reported for migration unless --force is given."
  else
    info "All installed skills match this release."
  fi
}

# Resolves which skills the project should have. Runs before any write.
resolve_skill_selection() {
  local is_join="$1" agents=AGENTS.md current
  load_skill_catalog
  compute_skill_states
  if [ "$is_join" -eq 1 ] && agents_has_skills_line "$agents"; then
    current="$(stored_skill_selection "$agents")"
  else
    current="$(all_skills_csv)"
  fi
  if [ "$SKILLS_REQUESTED" -eq 1 ]; then
    SELECTED_SKILLS="$(parse_skill_request "$SKILLS_REQUEST")"
  elif [ "$INTERACTIVE_REQUESTED" -eq 1 ] || interactive_available; then
    { : < /dev/tty; } 2>/dev/null || fail "--interactive needs a terminal; use --skills LIST instead"
    run_picker "Choose skills to install in $(join_roots)" "$(all_skills_csv)" "$current"
    SELECTED_SKILLS="$PICKED"
    if print_skill_plan "$SELECTED_SKILLS" > /dev/tty; then
      confirm_skill_plan "$SELECTED_SKILLS"
    fi
  else
    SELECTED_SKILLS="$current"
  fi
}

# Replaces a file's content through a temporary sibling and a rename, so an
# interruption never leaves it truncated. Symbolic links are refused because
# writing through one could change a file outside the project.
replace_file_atomically() {
  local target="$1" content="$2" temporary
  [ ! -L "$target" ] || fail "$target is a symbolic link; replace it with a regular file before changing the skill selection"
  temporary="$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")" || fail "cannot create a temporary file next to $target"
  cp -p "$target" "$temporary" 2>/dev/null || true
  cat "$content" > "$temporary"
  mv -f "$temporary" "$target"
}

# Renders the AGENTS.md selection before any write. Prints nothing and returns
# 1 when AGENTS.md does not need to change.
prepare_agents_selection() {
  local agents=AGENTS.md rendered
  [ -f "$agents" ] || return 1
  if ! grep -q '<!-- template: AGENTS ' "$agents"; then
    [ "$SELECTED_SKILLS" = "$(all_skills_csv)" ] || warn "AGENTS.md is not toolkit-managed; the skill selection was not recorded"
    return 1
  fi
  rendered="$(skill_work_dir)/AGENTS.selection.md"
  render_agents_selection "$agents" "$rendered" "$SELECTED_SKILLS" || fail "could not record the skill selection in AGENTS.md"
  if cmp -s "$agents" "$rendered"; then return 1; fi
  [ ! -L "$agents" ] || fail "AGENTS.md is a symbolic link; replace it with a regular file before changing the skill selection"
  return 0
}

# Adds, updates, or removes the AGENTS.md skills line to match the selection.
update_agents_selection() {
  local agents=AGENTS.md rendered proof was_owned=0
  prepare_agents_selection || return 0
  rendered="$(skill_work_dir)/AGENTS.selection.md"
  info " ~ AGENTS.md (skills: $(if [ "$SELECTED_SKILLS" = "$(all_skills_csv)" ]; then printf 'all'; else skills_line_value "$SELECTED_SKILLS"; fi))"
  show_diff "$agents" "$rendered" AGENTS.md current updated
  proof="$(recorded_file_proof AGENTS.md)"
  [ -z "$proof" ] || [ "$(fingerprint "$agents")" != "$proof" ] || was_owned=1
  replace_file_atomically "$agents" "$rendered"
  [ "$was_owned" -eq 0 ] || record_ownership AGENTS.md file "$(fingerprint "$agents")"
}

install_project() {
  [ ! -f manifest.tsv ] || [ ! -f install.sh ] || [ ! -d skills ] || fail "the toolkit repository is exempt from --project installation"
  local is_join=0 legacy_platform stored_project_types stored_technologies catalog
  OWNERSHIP_SCOPE=project
  PROJECT_ROOT="$(pwd -P)"
  OWNERSHIP_FILE="$(pwd)/.mindflayer-managed.tsv"
  validate_ownership_file
  SKILL_ROOTS=()
  local skill_root
  while IFS= read -r skill_root; do
    SKILL_ROOTS+=("$skill_root")
  done < <(selected_skill_roots project)
  if [ "$SKILLS_STATUS_ONLY" -eq 1 ]; then
    [ "${#SKILL_ROOTS[@]}" -gt 0 ] || fail "--skills-status needs a tool with a skill root: claude, codex, or copilot"
    print_skills_status
    return 0
  fi
  if [ "${#SKILL_ROOTS[@]}" -eq 0 ] && { [ "$SKILLS_REQUESTED" -eq 1 ] || [ "$INTERACTIVE_REQUESTED" -eq 1 ]; }; then
    fail "the selected tools have no project skill root; skills are used by claude, codex, and copilot"
  fi
  if [ -f AGENTS.md ] && grep -q '<!-- template: AGENTS ' AGENTS.md; then is_join=1; fi

  [ -z "$PROFILE" ] || { [ -z "$PROJECT_TYPES" ] && [ -z "$TECHNOLOGIES" ]; } || fail "--profile cannot be combined with --project-types or --technologies"

  if [ "$is_join" -eq 1 ]; then
    legacy_platform="$(sed -n 's/^[[:space:]]*- \*\*platform:\*\*[[:space:]]*//p' AGENTS.md | head -1)"
    stored_project_types="$(sed -n 's/^[[:space:]]*- \*\*project types:\*\*[[:space:]]*//p' AGENTS.md | head -1)"
    stored_technologies="$(sed -n 's/^[[:space:]]*- \*\*technologies:\*\*[[:space:]]*//p' AGENTS.md | head -1)"
    if [ -n "$stored_project_types" ] || [ -n "$stored_technologies" ]; then
      [ -n "$stored_project_types" ] && [ -n "$stored_technologies" ] || fail "AGENTS.md contains partial composable project metadata"
      [ -z "$PROFILE" ] || fail "--profile cannot be used with composable AGENTS.md metadata"
      catalog="$(fetch_temp config/technology-catalog.tsv)"
      stored_project_types="$(canonicalize_catalog_list "$stored_project_types" project-type --project-types "$catalog")"
      stored_technologies="$(canonicalize_catalog_list "$stored_technologies" technology --technologies "$catalog")"
      if [ -n "$PROJECT_TYPES" ]; then
        PROJECT_TYPES="$(canonicalize_catalog_list "$PROJECT_TYPES" project-type --project-types "$catalog")"
        [ "$PROJECT_TYPES" = "$stored_project_types" ] || fail "--project-types does not match AGENTS.md"
      else
        PROJECT_TYPES="$stored_project_types"
      fi
      if [ -n "$TECHNOLOGIES" ]; then
        TECHNOLOGIES="$(canonicalize_catalog_list "$TECHNOLOGIES" technology --technologies "$catalog")"
        [ "$TECHNOLOGIES" = "$stored_technologies" ] || fail "--technologies does not match AGENTS.md"
      else
        TECHNOLOGIES="$stored_technologies"
      fi
      PROJECT_MODE="composable"
    else
      [ -n "$legacy_platform" ] || fail "AGENTS.md does not contain supported project metadata"
      [ -z "$PROJECT_TYPES" ] && [ -z "$TECHNOLOGIES" ] || fail "composable flags cannot be used with legacy AGENTS.md metadata"
      if [ -n "$PROFILE" ]; then
        [ "$PROFILE" = "$legacy_platform" ] || fail "--profile does not match AGENTS.md"
      else
        PROFILE="$legacy_platform"
      fi
      validate_profile
      PROJECT_MODE="legacy"
    fi
  elif [ -n "$PROFILE" ]; then
    validate_profile
    PROJECT_MODE="legacy"
  else
    [ -n "$PROJECT_TYPES" ] || fail "--project-types is required for a new project install"
    [ -n "$TECHNOLOGIES" ] || fail "--technologies is required for a new project install"
    catalog="$(fetch_temp config/technology-catalog.tsv)"
    PROJECT_TYPES="$(canonicalize_catalog_list "$PROJECT_TYPES" project-type --project-types "$catalog")"
    TECHNOLOGIES="$(canonicalize_catalog_list "$TECHNOLOGIES" technology --technologies "$catalog")"
    PROJECT_MODE="composable"
  fi

  if [ "$is_join" -eq 0 ]; then
    [ -n "$CLIENT_NAME" ] || fail "--client is required for a new project install"
    [ "$PROJECT_MODE" != legacy ] || [ -n "$CLIENT_PREFIX" ] || fail "--prefix is required for a legacy profile install"
  fi

  # Every question is asked before the first write, so cancelling changes nothing.
  if [ "${#SKILL_ROOTS[@]}" -gt 0 ]; then
    resolve_skill_selection "$is_join"
    if [ "$is_join" -eq 1 ]; then prepare_agents_selection > /dev/null || true; fi
  fi

  if [ "$is_join" -eq 0 ]; then
    local template rendered selected_rendered
    rendered="$(mktemp)"
    if [ "$PROJECT_MODE" = legacy ]; then
      template="$(fetch_temp templates/AGENTS.md)"
      replace_tokens "$template" "$rendered"
    else
      template="$(fetch_temp templates/AGENTS-composable.md)"
      replace_composable_tokens "$template" "$rendered"
    fi
    if [ "${#SKILL_ROOTS[@]}" -gt 0 ]; then
      selected_rendered="$(skill_work_dir)/AGENTS.new.md"
      render_agents_selection "$rendered" "$selected_rendered" "$SELECTED_SKILLS" || fail "could not record the skill selection in AGENTS.md"
      cat "$selected_rendered" > "$rendered"
    fi
    install_file "$rendered" AGENTS.md
    rm -f "$rendered"
  else
    info " = AGENTS.md (join mode)"
  fi

  local manifest name relative
  manifest="$PREFLIGHT_MANIFEST"

  if [ "${#SKILL_ROOTS[@]}" -gt 0 ]; then
    [ "$is_join" -eq 0 ] || update_agents_selection
    for skill_root in "${SKILL_ROOTS[@]}"; do
      reconcile_skill_files "$manifest" "$skill_root" "$SELECTED_SKILLS"
      while IFS= read -r name; do
        list_contains "$name" "$SELECTED_SKILLS" || remove_empty_skill_dirs "$skill_root" "$name"
      done < <(skill_names_list)
    done
    while IFS=$'\t' read -r name relative; do
      list_contains "$name" "$SELECTED_SKILLS" || continue
      for skill_root in "${SKILL_ROOTS[@]}"; do
        install_skill_file "$name" "$relative" "$skill_root"
      done
    done < "$(skill_work_dir)/skill-files.tsv"
  fi

  local agent
  for agent in "${AGENTS_TO_INSTALL[@]}"; do
    case "$agent" in
      claude)
        if [ "$PROJECT_MODE" = legacy ]; then
          source="$(fetch_temp "settings/claude/settings-$PROFILE.json")"
        else
          source="$(mktemp)"
          compose_claude_settings "$(fetch_temp settings/claude/technology-permissions.tsv)" "$source"
        fi
        install_file "$source" .claude/settings.json
        [ "$PROJECT_MODE" = legacy ] || rm -f "$source"
        source="$(fetch_temp CLAUDE.md)"
        install_file "$source" CLAUDE.md
        migrate_legacy_project_artifacts claude
        ;;
      codex) migrate_legacy_project_artifacts codex; info " = AGENTS.md (Codex native)" ;;
      gemini) source="$(fetch_temp GEMINI.md)"; migrate_legacy_project_artifacts gemini; install_file "$source" GEMINI.md ;;
      cursor) migrate_legacy_project_artifacts cursor; info " = AGENTS.md (Cursor native)" ;;
      copilot) migrate_legacy_project_artifacts copilot; info " = AGENTS.md (Copilot native)" ;;
    esac
  done
  if [ ! -d docs/adr ]; then
    mkdir -p docs/adr
    record_ownership "$(pwd)/docs/adr" directory empty-only
  fi
  append_gitignore_exact .claude/settings.local.json
  append_gitignore_exact CLAUDE.local.md
  append_gitignore_exact .mindflayer-managed.tsv
  info "Configured project for: ${AGENTS_TO_INSTALL[*]}"
  if [ "${#SKILL_ROOTS[@]}" -gt 0 ]; then
    info "Skills: $(if [ "$SELECTED_SKILLS" = "$(all_skills_csv)" ]; then printf 'all'; else skills_line_value "$SELECTED_SKILLS"; fi)"
  fi
  print_migration_summary
}

main() {
  parse_args "$@"
  [ -n "$INSTALL_MODE" ] || fail "specify exactly one of --global or --project"
  detect_platform
  setup_color
  if [ "$INSTALL_MODE" = global ] && { [ "$SKILLS_REQUESTED" -eq 1 ] || [ "$INTERACTIVE_REQUESTED" -eq 1 ] || [ "$SKILLS_STATUS_ONLY" -eq 1 ]; }; then
    fail "--skills, --interactive, and --skills-status apply to --project installs only"
  fi
  if [ "$SKILLS_REQUESTED" -eq 1 ] && [ "$INTERACTIVE_REQUESTED" -eq 1 ]; then
    fail "choose skills either with --skills or with --interactive, not both"
  fi
  if [ "$SKILLS_STATUS_ONLY" -eq 1 ] && { [ "$SKILLS_REQUESTED" -eq 1 ] || [ "$INTERACTIVE_REQUESTED" -eq 1 ] || [ "$REPLACE" -eq 1 ]; }; then
    fail "--skills-status only reports; it cannot be combined with --skills, --interactive, or --force"
  fi
  validate_tools
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mindflayer-install.XXXXXX")" || fail "cannot create a temporary directory"
  BUNDLE_ROOT="$(source_root)"
  PREFLIGHT_MANIFEST="$(fetch_temp manifest.tsv)"
  validate_manifest "$PREFLIGHT_MANIFEST"
  validate_bundle_sources "$PREFLIGHT_MANIFEST"
  case "$INSTALL_MODE" in global) install_global ;; project) install_project ;; esac
}

main "$@"
exit "$EXIT_STATUS"

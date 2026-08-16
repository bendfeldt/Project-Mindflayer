#!/usr/bin/env bash
set -euo pipefail

VERSION="3.6.0"
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
CURRENT_PLATFORM=""

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
  --force           Authorize replacement; existing files are backed up first
  --help            Show this help

Existing files are preserved unless --force explicitly authorizes replacement.
The toolkit repository itself is not a valid --project target.

Requirements:
  Linux or macOS with Bash 3.2+, standard Unix utilities, a complete verified
  release bundle, and write access to the selected user or project paths.
  Windows 10/11 uses install.ps1 with PowerShell 7.4+; see
  docs/system-requirements.md for complete and capability-specific requirements.
USAGE
}

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
  local path="$1" record kind proof artifact
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
        warn "preserved obsolete $path (modified or type changed)"
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
  info " - $path (obsolete)"
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

reconcile_skill_files() {
  local manifest="$1" root="$2" expected snapshot path type consumers platforms
  [ -n "$OWNERSHIP_FILE" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  expected="$(mktemp)"
  snapshot="$(mktemp)"
  while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
    case "$type" in skill|skill-resource) ;; *) continue ;; esac
    consumer_matches "$consumers" project:skills || continue
    platform_matches "$platforms" || continue
    printf '%s\n' "$root/${path#skills/}" >> "$expected"
  done < <(manifest_rows "$manifest")
  cp "$OWNERSHIP_FILE" "$snapshot"
  while IFS=$'\t' read -r path _kind _proof; do
    case "$path" in "$root"/*) ;; *) continue ;; esac
    grep -Fqx "$path" "$expected" || remove_verified_owned_artifact "$path"
  done < "$snapshot"
  rm -f "$expected" "$snapshot"
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
    install.sh|install.ps1) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
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

install_project() {
  [ ! -f manifest.tsv ] || [ ! -f install.sh ] || [ ! -d skills ] || fail "the toolkit repository is exempt from --project installation"
  local is_join=0 legacy_platform stored_project_types stored_technologies catalog
  OWNERSHIP_SCOPE=project
  PROJECT_ROOT="$(pwd -P)"
  OWNERSHIP_FILE="$(pwd)/.mindflayer-managed.tsv"
  validate_ownership_file
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
    local template rendered
    rendered="$(mktemp)"
    if [ "$PROJECT_MODE" = legacy ]; then
      template="$(fetch_temp templates/AGENTS.md)"
      replace_tokens "$template" "$rendered"
    else
      template="$(fetch_temp templates/AGENTS-composable.md)"
      replace_composable_tokens "$template" "$rendered"
    fi
    install_file "$rendered" AGENTS.md
    rm -f "$rendered"
  else
    info " = AGENTS.md (join mode)"
  fi

  local manifest path type consumers platforms source destination skill_root
  local skill_roots=()
  manifest="$PREFLIGHT_MANIFEST"

  while IFS= read -r skill_root; do
    skill_roots+=("$skill_root")
  done < <(selected_skill_roots project)

  if [ "${#skill_roots[@]}" -gt 0 ]; then
    for skill_root in "${skill_roots[@]}"; do
      reconcile_skill_files "$manifest" "$skill_root"
    done
    while IFS=$'\t' read -r path type _version consumers _ownership platforms; do
      case "$type" in skill|skill-resource) ;; *) continue ;; esac
      consumer_matches "$consumers" project:skills || continue
      platform_matches "$platforms" || continue
      source="$(fetch_temp "$path")"
      for skill_root in "${skill_roots[@]}"; do
        destination="$skill_root/${path#skills/}"
        install_file "$source" "$destination"
      done
    done < <(manifest_rows "$manifest")
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
}

main() {
  parse_args "$@"
  [ -n "$INSTALL_MODE" ] || fail "specify exactly one of --global or --project"
  detect_platform
  validate_tools
  BUNDLE_ROOT="$(source_root)"
  PREFLIGHT_MANIFEST="$(fetch_temp manifest.tsv)"
  validate_manifest "$PREFLIGHT_MANIFEST"
  validate_bundle_sources "$PREFLIGHT_MANIFEST"
  case "$INSTALL_MODE" in global) install_global ;; project) install_project ;; esac
}

main "$@"

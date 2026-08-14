#!/usr/bin/env bash
set -euo pipefail

VERSION="3.0.0"
REPO_URL="https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main"
KNOWN_TOOLS="claude codex gemini cursor copilot"
VALID_PROFILES="terraform databricks fabric"

INSTALL_MODE=""
SELECTED_TOOLS=""
PROFILE=""
CLIENT_NAME=""
CLIENT_PREFIX=""
LOCAL=0
REPLACE=0
TMP_ROOT=""
OWNERSHIP_FILE=""
AGENTS_TO_INSTALL=()

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
  --profile NAME    terraform, databricks, or fabric (project mode)
  --client NAME     Client name (new project install)
  --prefix PREFIX   Resource prefix (new project install)
  --force           Authorize replacement; existing files are backed up first
  --local           Read from this checkout instead of GitHub
  --help            Show this help

Existing files are preserved unless --force explicitly authorizes replacement.
The toolkit repository itself is not a valid --project target.
USAGE
}

cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

require_value() {
  [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#--}" = "$2" ] || fail "$1 requires a value"
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
      --client) require_value "$1" "${2:-}"; shift; CLIENT_NAME="$1" ;;
      --prefix) require_value "$1" "${2:-}"; shift; CLIENT_PREFIX="$1" ;;
      --force) REPLACE=1 ;;
      --local) LOCAL=1 ;;
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

fetch() {
  local path="$1" destination="$2"
  mkdir -p "$(dirname "$destination")"
  if [ "$LOCAL" -eq 1 ]; then
    cp "$(source_root)/$path" "$destination"
  else
    command -v curl >/dev/null 2>&1 || fail "curl is required for remote installation"
    curl -fsSL --proto '=https' "$REPO_URL/$path" -o "$destination"
  fi
}

fetch_temp() {
  local path="$1"
  if [ -z "$TMP_ROOT" ]; then TMP_ROOT="$(mktemp -d)"; fi
  local destination="$TMP_ROOT/$path"
  fetch "$path" "$destination"
  printf '%s' "$destination"
}

timestamp() { date '+%Y%m%d%H%M%S'; }

fingerprint() {
  cksum "$1" | awk '{print $1 ":" $2}'
}

record_ownership() {
  local path="$1" kind="$2" proof="$3" temporary
  [ -n "$OWNERSHIP_FILE" ] || return 0
  mkdir -p "$(dirname "$OWNERSHIP_FILE")"
  temporary="${OWNERSHIP_FILE}.tmp"
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

manifest_rows() {
  awk -F '\t' 'NF >= 5 && $1 !~ /^#/ {print}' "$1"
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

skill_names() {
  awk -F '\t' '$2 == "skill" {sub("skills/", "", $1); sub("/SKILL.md", "", $1); print $1}' "$1"
}

global_destination() {
  local path="$1"
  case "$path" in
    install.sh) printf '%s/.ai-toolkit/install.sh' "$HOME" ;;
    README.md|how-to-guide.md|LICENSE) printf '%s/.ai-toolkit/docs/%s' "$HOME" "$path" ;;
    global/AGENTS.md) printf '%s/.ai-toolkit/AGENTS.md' "$HOME" ;;
    templates/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    docs/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    skills/*) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    tools/*) printf '%s/.ai-toolkit/%s' "$HOME" "${path#tools/}" ;;
    stores.yml|manifest.tsv) printf '%s/.ai-toolkit/%s' "$HOME" "$path" ;;
    settings/claude/settings-terraform.json|settings/claude/settings-databricks.json|settings/claude/settings-fabric.json)
      printf '%s/.ai-toolkit/templates/settings/%s' "$HOME" "$(basename "$path")" ;;
    settings/claude/settings-global.json)
      printf '%s/.ai-toolkit/templates/settings/%s' "$HOME" "$(basename "$path")" ;;
    settings/codex/*) printf '%s/.ai-toolkit/templates/codex/%s' "$HOME" "$(basename "$path")" ;;
    settings/copilot/*) printf '%s/.ai-toolkit/templates/copilot/%s' "$HOME" "$(basename "$path")" ;;
    settings/gemini/*) printf '%s/.ai-toolkit/templates/gemini/%s' "$HOME" "$(basename "$path")" ;;
    settings/cursor/*) printf '%s/.ai-toolkit/templates/cursor/%s' "$HOME" "$(basename "$path")" ;;
    settings/claude/scaffold/*) printf '%s/.ai-toolkit/templates/%s' "$HOME" "$path" ;;
    *) return 1 ;;
  esac
}

install_global() {
  local manifest source path type consumers destination
  manifest="$(fetch_temp manifest.tsv)"
  mkdir -p "$HOME/.ai-toolkit"
  OWNERSHIP_FILE="$HOME/.ai-toolkit/managed.tsv"
  install_file "$manifest" "$HOME/.ai-toolkit/manifest.tsv" "manifest.tsv"

  while IFS=$'\t' read -r path type _version consumers _ownership; do
    global_consumer_selected "$consumers" || continue
    source="$(fetch_temp "$path")"
    destination="$(global_destination "$path")" || fail "no global destination for $path"
    install_file "$source" "$destination"
    [ "$type" != script ] || chmod +x "$destination"
  done < <(manifest_rows "$manifest")

  local baseline="$HOME/.ai-toolkit/AGENTS.md" agent skill
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

  while IFS= read -r skill; do
    is_selected claude && install_link "$HOME/.ai-toolkit/skills/$skill" "$HOME/.claude/skills/$skill"
    is_selected copilot && install_link "$HOME/.ai-toolkit/skills/$skill" "$HOME/.copilot/skills/$skill"
  done < <(skill_names "$manifest")

  # Commit the release stamp only after every requested artifact succeeds.
  printf '%s\n' "$VERSION" > "$HOME/.ai-toolkit/version.tmp"
  mv "$HOME/.ai-toolkit/version.tmp" "$HOME/.ai-toolkit/version"
  record_ownership "$HOME/.ai-toolkit/version" file "$(fingerprint "$HOME/.ai-toolkit/version")"
  info "Installed toolkit $VERSION for: ${AGENTS_TO_INSTALL[*]}"
}

validate_profile() {
  contains_word "$PROFILE" "$VALID_PROFILES" || fail "invalid profile '$PROFILE'; expected: ${VALID_PROFILES// /,}"
}

replace_tokens() {
  local source="$1" destination="$2" repo_type safe_client safe_prefix
  case "$PROFILE" in terraform) repo_type="infrastructure" ;; *) repo_type="data-platform" ;; esac
  safe_client="$(printf '%s' "$CLIENT_NAME" | sed 's/[&|\\]/\\&/g')"
  safe_prefix="$(printf '%s' "$CLIENT_PREFIX" | sed 's/[&|\\]/\\&/g')"
  sed -e "s|{CLIENT_NAME}|$safe_client|g" -e "s|{PLATFORM}|$PROFILE|g" -e "s|{REPO_TYPE}|$repo_type|g" -e "s|{prefix}|$safe_prefix|g" "$source" > "$destination"
}

project_destination() {
  local path="$1"
  case "$path" in
    skills/*) printf '.claude/%s' "$path" ;;
    settings/claude/scaffold/*) printf '.claude/%s' "${path#settings/claude/scaffold/}" ;;
    *) return 1 ;;
  esac
}

append_gitignore_exact() {
  local entry="$1"
  touch .gitignore
  if ! grep -Fqx -- "$entry" .gitignore; then
    printf '%s\n' "$entry" >> .gitignore
    record_ownership "$(pwd)/.gitignore" line "$entry"
  fi
}

install_project() {
  [ ! -f manifest.tsv ] || [ ! -f install.sh ] || [ ! -d skills ] || fail "the toolkit repository is exempt from --project installation"
  local is_join=0
  OWNERSHIP_FILE="$(pwd)/.mindflayer-managed.tsv"
  if [ -f AGENTS.md ] && grep -q '<!-- template: AGENTS ' AGENTS.md; then is_join=1; fi
  if [ "$is_join" -eq 1 ] && [ -z "$PROFILE" ]; then
    PROFILE="$(sed -n 's/^[[:space:]]*- \*\*platform:\*\*[[:space:]]*//p' AGENTS.md | head -1)"
  fi
  [ -n "$PROFILE" ] || fail "--profile is required for a new project install"
  validate_profile
  if [ "$is_join" -eq 0 ]; then
    [ -n "$CLIENT_NAME" ] || fail "--client is required for a new project install"
    [ -n "$CLIENT_PREFIX" ] || fail "--prefix is required for a new project install"
    local template rendered
    template="$(fetch_temp templates/AGENTS.md)"
    rendered="$(mktemp)"
    replace_tokens "$template" "$rendered"
    install_file "$rendered" AGENTS.md
    rm -f "$rendered"
  else
    info " = AGENTS.md (join mode)"
  fi

  local manifest path type consumers source destination
  manifest="$(fetch_temp manifest.tsv)"
  if is_selected claude || is_selected copilot; then
    while IFS=$'\t' read -r path type _version consumers _ownership; do
      case "$type" in skill|skill-resource) ;; *) continue ;; esac
      source="$(fetch_temp "$path")"
      destination="$(project_destination "$path")"
      install_file "$source" "$destination"
    done < <(manifest_rows "$manifest")
  fi

  local agent
  for agent in "${AGENTS_TO_INSTALL[@]}"; do
    case "$agent" in
      claude)
        source="$(fetch_temp "settings/claude/settings-$PROFILE.json")"
        install_file "$source" .claude/settings.json
        while IFS=$'\t' read -r path type _version consumers _ownership; do
          [ "$type" = scaffold ] || continue
          source="$(fetch_temp "$path")"; destination="$(project_destination "$path")"
          install_file "$source" "$destination"
        done < <(manifest_rows "$manifest")
        ;;
      codex) source="$(fetch_temp settings/codex/codex.md)"; install_file "$source" codex.md ;;
      gemini) source="$(fetch_temp settings/gemini/gemini.md)"; install_file "$source" gemini.md ;;
      cursor) source="$(fetch_temp settings/cursor/cursor.md)"; install_file "$source" .cursor/rules/project.md ;;
      copilot) install_link ../AGENTS.md .github/copilot-instructions.md ;;
    esac
  done
  if [ ! -d docs/adr ]; then
    mkdir -p docs/adr
    record_ownership "$(pwd)/docs/adr" directory empty-only
  fi
  append_gitignore_exact .claude/settings.local.json
  append_gitignore_exact CLAUDE.local.md
  info "Configured project for: ${AGENTS_TO_INSTALL[*]}"
}

main() {
  parse_args "$@"
  [ -n "$INSTALL_MODE" ] || fail "specify exactly one of --global or --project"
  validate_tools
  case "$INSTALL_MODE" in global) install_global ;; project) install_project ;; esac
}

main "$@"

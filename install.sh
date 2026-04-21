#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Consultant Toolkit Installer
# Cross-platform (macOS + Linux) — curl-installable or run from local checkout
# =============================================================================

VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main"

# --- Defaults ----------------------------------------------------------------

INSTALL_MODE=""
SELECTED_TOOLS=""
FORCE=0
PROFILE=""
LOCAL=""
CLIENT_NAME=""
CLIENT_PREFIX=""

# --- Colors (with fallback for dumb terminals) -------------------------------

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN="" RED="" YELLOW="" BOLD="" RESET=""
fi

# --- Helpers -----------------------------------------------------------------

info()  { printf "%s\n" "$1"; }
ok()    { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "  %s⚠%s %s\n" "$YELLOW" "$RESET" "$1"; }
err()   { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1"; }

usage() {
    cat <<'USAGE'
Usage: install.sh [OPTIONS]

Options:
  --global              Install to user-level (~/.claude/, ~/.codex/, etc.)
  --project             Install to current directory (default if --global not set)
  --tools TOOLS         Comma-separated list of agents: claude,codex,gemini,cursor,copilot
  --force               Overwrite existing files without prompting
  --profile PROFILE     Platform profile: terraform, databricks, fabric
  --local               Use local checkout instead of fetching from GitHub
  --client NAME         Client name for project install (e.g., PostNord)
  --prefix PREFIX       Resource prefix for project install (e.g., pn)
  --help                Show this help

Examples:
  # Global install (interactive agent selection)
  bash install.sh --global

  # Global install via curl
  bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global

  # Project setup with profile
  bash install.sh --profile terraform --tools claude,codex

USAGE
    exit 0
}

# --- Source resolution -------------------------------------------------------

resolve_source() {
    if [ -n "$LOCAL" ]; then
        return
    fi

    # Detect if running from curl pipe (stdin is script, not a real file)
    if [ -f "${BASH_SOURCE[0]:-}" ]; then
        local script_path
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # Verify it looks like the repo (global/ dir exists)
        if [ -d "$script_path/global" ]; then
            LOCAL=1
            SCRIPT_DIR="$script_path"
            return
        fi
    fi

    # Not local — use remote
    LOCAL=0
}

TMPDIR_CLEANUP=""

fetch_file() {
    local rel_path="$1"
    local dest="$2"

    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    if [ "$LOCAL" = "1" ]; then
        cp "$SCRIPT_DIR/$rel_path" "$dest"
    else
        if ! curl -sfL --proto =https "${REPO_URL}/${rel_path}" -o "$dest"; then
            err "Failed to fetch: $rel_path"
            return 1
        fi
    fi
}

# Fetch a file to a temp location and print the path
# Uses full relative path to avoid basename collisions (e.g., multiple SKILL.md)
fetch_to_tmp() {
    local rel_path="$1"
    if [ -z "$TMPDIR_CLEANUP" ]; then
        TMPDIR_CLEANUP="$(mktemp -d)"
    fi
    local tmp_file="$TMPDIR_CLEANUP/$rel_path"
    mkdir -p "$(dirname "$tmp_file")"
    fetch_file "$rel_path" "$tmp_file"
    printf "%s" "$tmp_file"
}

cleanup_tmp() {
    if [ -n "$TMPDIR_CLEANUP" ] && [ -d "$TMPDIR_CLEANUP" ]; then
        rm -rf "$TMPDIR_CLEANUP"
    fi
}
trap cleanup_tmp EXIT

# --- Flag parsing ------------------------------------------------------------

require_arg() {
    if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
        err "$1 requires a value"
        exit 1
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --global)   INSTALL_MODE="global" ;;
            --project)  INSTALL_MODE="project" ;;
            --tools)    require_arg "$1" "${2:-}"; shift; SELECTED_TOOLS="$1" ;;
            --force)    FORCE=1 ;;
            --profile)  require_arg "$1" "${2:-}"; shift; PROFILE="$1" ;;
            --local)    LOCAL=1 ;;
            --client)   require_arg "$1" "${2:-}"; shift; CLIENT_NAME="$1" ;;
            --prefix)   require_arg "$1" "${2:-}"; shift; CLIENT_PREFIX="$1" ;;
            --help|-h)  usage ;;
            *)          err "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}

# --- Agent detection ---------------------------------------------------------

KNOWN_AGENTS=(claude codex gemini cursor copilot)
DETECTED=()

detect_agents() {
    DETECTED=()
    for agent in "${KNOWN_AGENTS[@]}"; do
        case "$agent" in
            copilot)
                if command -v gh >/dev/null 2>&1; then
                    DETECTED+=("copilot")
                fi
                ;;
            *)
                if command -v "$agent" >/dev/null 2>&1; then
                    DETECTED+=("$agent")
                fi
                ;;
        esac
    done
}

is_detected() {
    local needle="$1"
    for d in ${DETECTED[@]+"${DETECTED[@]}"}; do
        [ "$d" = "$needle" ] && return 0
    done
    return 1
}

# --- Agent selection prompt --------------------------------------------------

AGENTS_TO_INSTALL=()

prompt_agent_selection() {
    if [ -n "$SELECTED_TOOLS" ]; then
        IFS=',' read -ra AGENTS_TO_INSTALL <<< "$SELECTED_TOOLS"
        return
    fi

    if ! [ -t 0 ]; then
        err "Non-interactive shell detected. Use --tools to specify agents."
        exit 1
    fi

    info ""
    info "${BOLD}Detected coding agents:${RESET}"

    local defaults=()
    for i in "${!KNOWN_AGENTS[@]}"; do
        local num=$((i + 1))
        local agent="${KNOWN_AGENTS[$i]}"
        if is_detected "$agent"; then
            local note=""
            [ "$agent" = "copilot" ] && note=" (via gh)"
            printf "  [%d] %-10s %s✓ installed%s%s\n" "$num" "$agent" "$GREEN" "$RESET" "$note"
            defaults+=("$num")
        else
            printf "  [%d] %-10s %s✗ not found%s\n" "$num" "$agent" "$RED" "$RESET"
        fi
    done

    local default_str=""
    if [ ${#defaults[@]} -gt 0 ]; then
        default_str="$(IFS=','; echo "${defaults[*]}")"
    fi

    info ""
    read -r -p "Select agents to configure [${default_str}]: " selection

    if [ -z "$selection" ]; then
        selection="$default_str"
    fi

    if [ -z "$selection" ]; then
        err "No agents detected or selected. Install an agent CLI first, or use --tools."
        exit 1
    fi

    AGENTS_TO_INSTALL=()
    IFS=',' read -ra nums <<< "$selection"
    for n in "${nums[@]}"; do
        n="$(echo "$n" | tr -d ' ')"
        if [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le 5 ] 2>/dev/null; then
            AGENTS_TO_INSTALL+=("${KNOWN_AGENTS[$((n - 1))]}")
        else
            warn "Ignoring invalid selection: $n"
        fi
    done

    if [ ${#AGENTS_TO_INSTALL[@]} -eq 0 ]; then
        err "No agents selected. Exiting."
        exit 1
    fi

    info ""
    info "Configuring: ${BOLD}${AGENTS_TO_INSTALL[*]}${RESET}"
}

# --- Install mode prompt -----------------------------------------------------

prompt_install_mode() {
    if [ -n "$INSTALL_MODE" ]; then
        return
    fi

    if ! [ -t 0 ]; then
        err "Non-interactive shell. Use --global or --project to specify mode."
        exit 1
    fi

    info ""
    info "${BOLD}Install mode:${RESET}"
    info "  [1] Global  — install skills, docs, settings to ~/  (run once)"
    info "  [2] Project — set up AGENTS.md + settings in current repo"
    info ""
    read -r -p "Select mode [1]: " mode_choice

    case "${mode_choice:-1}" in
        1) INSTALL_MODE="global" ;;
        2) INSTALL_MODE="project" ;;
        *) err "Invalid choice"; exit 1 ;;
    esac
}

# --- Safe copy with overwrite protection -------------------------------------

safe_copy() {
    local src="$1"
    local dest="$2"

    # Use <parent>/<basename> when the basename is generic (e.g., SKILL.md)
    # so install output identifies which skill was copied instead of printing
    # "SKILL.md" eight times.
    local label
    label="$(basename "$dest")"
    if [ "$label" = "SKILL.md" ]; then
        label="$(basename "$(dirname "$dest")")/$label"
    fi

    if [ -f "$dest" ] && [ "$FORCE" != "1" ]; then
        if diff -q "$src" "$dest" >/dev/null 2>&1; then
            ok "$label (unchanged)"
            return
        fi
        if ! [ -t 0 ]; then
            warn "Skipped (exists, use --force): $dest"
            return
        fi
        read -r -p "  Overwrite $dest? [y/N]: " answer
        case "$answer" in
            y|Y) ;;
            *)   warn "Skipped: $dest"; return ;;
        esac
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"
    cp "$src" "$dest"
    ok "$label"
}

# safe_symlink <target-path> <link-path>
#   Creates a symlink at <link-path> pointing to <target-path>.
#   Idempotent: updates the link if it points elsewhere; prompts on real-file
#   collisions (matching safe_copy's interactive behaviour).
#   Used so a single skill directory in ~/.ai-toolkit/skills/ is the source
#   of truth and ~/.claude/skills/<name>/ symlinks there for Claude
#   auto-discovery (ADR-0002).
safe_symlink() {
    local target="$1"
    local link="$2"
    local label
    label="$(basename "$link")"

    local link_dir
    link_dir="$(dirname "$link")"
    mkdir -p "$link_dir"

    if [ -L "$link" ]; then
        local current
        current="$(readlink "$link")"
        if [ "$current" = "$target" ]; then
            ok "$label (symlink unchanged)"
            return
        fi
        ln -sfn "$target" "$link"
        ok "$label (symlink updated)"
        return
    fi

    if [ -e "$link" ] && [ "$FORCE" != "1" ]; then
        if ! [ -t 0 ]; then
            warn "Skipped (exists, use --force): $link"
            return
        fi
        read -r -p "  Replace $link with symlink? [y/N]: " answer
        case "$answer" in
            y|Y) ;;
            *)   warn "Skipped: $link"; return ;;
        esac
    fi

    rm -rf "$link" 2>/dev/null || true
    ln -s "$target" "$link"
    ok "$label (symlinked)"
}

# --- File manifests ----------------------------------------------------------

SKILL_FILES=(
    "skills/adr/SKILL.md"
    "skills/branch-cleanup/SKILL.md"
    "skills/kimball-model/SKILL.md"
    "skills/promote-adr/SKILL.md"
    "skills/setup-repo/SKILL.md"
    "skills/smart-commit/SKILL.md"
    "skills/smart-pr/SKILL.md"
    "skills/terraform-scaffold/SKILL.md"
    "skills/terraform-scaffold/references/azure-devops-pipelines.md"
    "skills/terraform-scaffold/references/fabric-modules.md"
)

DOC_FILES=(
    "docs/architecture.md"
    "docs/terraform-patterns.md"
    "docs/kimball-reference.md"
)

DECISION_FILES=(
    "docs/decisions/0001-agents-md-as-universal-repo-instruction-file.md"
    "docs/decisions/0002-skill-md-open-standard-for-cross-agent-skills.md"
    "docs/decisions/0003-thin-repo-templates-with-version-headers.md"
    "docs/decisions/0004-skills-at-repo-root-not-dot-claude.md"
    "docs/decisions/0005-entity-prefix-column-naming.md"
    "docs/decisions/0006-surrogate-key-business-key-pair.md"
    "docs/decisions/0007-scd2-audit-column-triplet.md"
    "docs/decisions/0008-role-playing-dimension-fk-naming.md"
    "docs/decisions/0009-five-layer-data-architecture.md"
    "docs/decisions/0010-lowercase-snake-case-naming.md"
    "docs/decisions/0011-tech-stack-conventions-as-adrs.md"
    "docs/decisions/0012-universal-baseline-plus-personal-layer.md"
    "docs/decisions/0013-revert-personal-overlay-and-client-adrs.md"
    "docs/decisions/platform/0011-safety-rules-for-all-agents.md"
    "docs/decisions/platform/0012-fabric-medallion-layers.md"
    "docs/decisions/platform/0013-fabric-semantic-model-design.md"
    "docs/decisions/platform/0014-fabric-git-integration-policy.md"
    "docs/decisions/platform/0015-fabric-adr-triggers.md"
    "docs/decisions/platform/0016-databricks-unity-catalog-structure.md"
    "docs/decisions/platform/0017-databricks-compute-defaults.md"
    "docs/decisions/platform/0018-databricks-adr-triggers.md"
    "docs/decisions/platform/0019-terraform-module-structure.md"
    "docs/decisions/platform/0020-terraform-adr-triggers.md"
)

TEMPLATE_FILES=(
    "templates/AGENTS.md"
)

CLAUDE_SETTINGS_FILES=(
    "settings/claude/settings-global.json"
    "settings/claude/settings-terraform.json"
    "settings/claude/settings-databricks.json"
    "settings/claude/settings-fabric.json"
)

CODEX_FILES=(
    "settings/codex/config.toml"
    "settings/codex/codex.md"
)

COPILOT_FILES=(
    "settings/copilot/copilot-instructions.md"
)

GEMINI_FILES=(
    "settings/gemini/settings.json"
    "settings/gemini/gemini.md"
)

CURSOR_FILES=(
    "settings/cursor/cursor.md"
)

SCRIPT_FILES=(
    "tools/check-template-update.sh"
    "tools/check-stores.sh"
    "tools/sync-global.sh"
    "tools/check-update.sh"
    "tools/uninstall.sh"
)

# =============================================================================
# GLOBAL INSTALL
# =============================================================================

is_agent_selected() {
    printf '%s\n' "${AGENTS_TO_INSTALL[@]}" | grep -qx "$1"
}

install_global() {
    info ""
    info "${BOLD}=== Global Install ===${RESET}"
    info ""

    local toolkit_home="$HOME/.ai-toolkit"
    mkdir -p "$toolkit_home"

    # --- Global baseline ---
    # The baseline is copied to ~/.ai-toolkit/AGENTS.md (source of truth for
    # sync-global.sh) and to each selected agent's config directory.
    local baseline_tmp
    baseline_tmp="$(fetch_to_tmp "global/AGENTS.md")"
    cp "$baseline_tmp" "$toolkit_home/AGENTS.md"
    ok "~/.ai-toolkit/AGENTS.md (baseline)"

    # --- Global config per agent ---
    info ""
    info "${BOLD}Global config:${RESET}"

    for agent in "${AGENTS_TO_INSTALL[@]}"; do
        case "$agent" in
            claude)
                if [ -f "$HOME/.claude/CLAUDE.md" ]; then
                    local backup="$HOME/.claude/CLAUDE.md.bak.$(date +%Y%m%d%H%M%S)"
                    cp "$HOME/.claude/CLAUDE.md" "$backup"
                    info "  Backed up: $backup"
                fi
                mkdir -p "$HOME/.claude"
                cp "$baseline_tmp" "$HOME/.claude/CLAUDE.md"
                ok "~/.claude/CLAUDE.md"
                ;;
            codex)
                mkdir -p "$HOME/.codex"
                cp "$baseline_tmp" "$HOME/.codex/AGENTS.md"
                ok "~/.codex/AGENTS.md"
                ;;
            gemini)
                mkdir -p "$HOME/.gemini"
                cp "$baseline_tmp" "$HOME/.gemini/GEMINI.md"
                ok "~/.gemini/GEMINI.md"
                ;;
            cursor)
                mkdir -p "$HOME/.cursor"
                cp "$baseline_tmp" "$HOME/.cursor/rules.md"
                ok "~/.cursor/rules.md"
                ;;
            copilot)
                mkdir -p "$HOME/.copilot"
                cp "$baseline_tmp" "$HOME/.copilot/copilot-instructions.md"
                ok "~/.copilot/copilot-instructions.md"
                ;;
        esac
    done

    # --- Skills ---
    # Install once to ~/.ai-toolkit/skills/ (agent-neutral source of truth).
    # Claude Code auto-discovers from ~/.claude/skills/, so symlink each
    # skill directory there when Claude is selected (ADR-0002). One symlink
    # per skill keeps the source of truth singular and also handles nested
    # files like skills/terraform-scaffold/references/*.md automatically.
    info ""
    info "${BOLD}Skills:${RESET}"
    for f in "${SKILL_FILES[@]}"; do
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        local toolkit_dest="$toolkit_home/$f"
        mkdir -p "$(dirname "$toolkit_dest")"
        safe_copy "$tmp" "$toolkit_dest"
    done
    if is_agent_selected claude; then
        mkdir -p "$HOME/.claude/skills"
        local TOOLKIT_SKILL_NAMES="adr branch-cleanup kimball-model promote-adr setup-repo smart-commit smart-pr terraform-scaffold"
        for name in $TOOLKIT_SKILL_NAMES; do
            safe_symlink "$toolkit_home/skills/$name" "$HOME/.claude/skills/$name"
        done
    fi

    # --- Reference docs ---
    info ""
    info "${BOLD}Reference docs:${RESET}"
    for f in "${DOC_FILES[@]}"; do
        local dest="$toolkit_home/$f"
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        safe_copy "$tmp" "$dest"
    done

    # --- Decision log ---
    info ""
    info "${BOLD}Decision log:${RESET}"
    for f in "${DECISION_FILES[@]}"; do
        local dest="$toolkit_home/$f"
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        safe_copy "$tmp" "$dest"
    done

    # --- Repo templates ---
    info ""
    info "${BOLD}Repo templates:${RESET}"
    for f in "${TEMPLATE_FILES[@]}"; do
        local dest="$toolkit_home/templates/$(basename "$f")"
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        safe_copy "$tmp" "$dest"
    done

    # --- Settings ---
    info ""
    info "${BOLD}Settings:${RESET}"

    # Claude global settings — only when claude is selected
    if is_agent_selected claude; then
        install_claude_global_settings
    fi

    # Per-profile settings templates (agent-neutral — used by all agents via project install)
    for f in "${CLAUDE_SETTINGS_FILES[@]}"; do
        local basename_f
        basename_f="$(basename "$f")"
        [ "$basename_f" = "settings-global.json" ] && continue
        local dest="$toolkit_home/templates/settings/$basename_f"
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        safe_copy "$tmp" "$dest"
    done

    # Codex templates
    if is_agent_selected codex; then
        for f in "${CODEX_FILES[@]}"; do
            local dest="$toolkit_home/templates/codex/$(basename "$f")"
            local tmp
            tmp="$(fetch_to_tmp "$f")"
            safe_copy "$tmp" "$dest"
        done
    fi

    # Copilot templates
    if is_agent_selected copilot; then
        for f in "${COPILOT_FILES[@]}"; do
            local dest="$toolkit_home/templates/copilot/$(basename "$f")"
            local tmp
            tmp="$(fetch_to_tmp "$f")"
            safe_copy "$tmp" "$dest"
        done
    fi

    # Gemini templates
    if is_agent_selected gemini; then
        for f in "${GEMINI_FILES[@]}"; do
            local dest="$toolkit_home/templates/gemini/$(basename "$f")"
            local tmp
            tmp="$(fetch_to_tmp "$f")"
            safe_copy "$tmp" "$dest"
        done
    fi

    # Cursor templates
    if is_agent_selected cursor; then
        for f in "${CURSOR_FILES[@]}"; do
            local dest="$toolkit_home/templates/cursor/$(basename "$f")"
            local tmp
            tmp="$(fetch_to_tmp "$f")"
            safe_copy "$tmp" "$dest"
        done
    fi

    # --- Utility scripts ---
    info ""
    info "${BOLD}Scripts:${RESET}"
    for f in "${SCRIPT_FILES[@]}"; do
        local dest="$toolkit_home/$(basename "$f")"
        local tmp
        tmp="$(fetch_to_tmp "$f")"
        safe_copy "$tmp" "$dest"
        chmod +x "$dest"
    done

    # --- Stores registry ---
    info ""
    info "${BOLD}Stores registry:${RESET}"
    local stores_tmp
    stores_tmp="$(fetch_to_tmp "stores.yml")"
    safe_copy "$stores_tmp" "$toolkit_home/stores.yml"

    # --- Version stamp ---
    info ""
    info "${BOLD}Version stamp:${RESET}"
    printf "%s\n" "$VERSION" > "$toolkit_home/version"
    ok "version ($VERSION)"

    # --- Summary ---
    info ""
    info "${BOLD}=== Global Install Complete ===${RESET}"
    info ""
    info "Agents configured: ${AGENTS_TO_INSTALL[*]}"
    info ""
    info "Next steps:"
    info "  1. Start an agent in any repo — it will detect missing AGENTS.md and offer setup"
    info "  2. Or run: ${BOLD}bash install.sh --project${RESET} from inside a repo"
    info ""
}

install_claude_global_settings() {
    local settings_tmp
    settings_tmp="$(fetch_to_tmp "settings/claude/settings-global.json")"
    local dest="$HOME/.claude/settings.json"

    if [ ! -f "$dest" ]; then
        mkdir -p "$HOME/.claude"
        cp "$settings_tmp" "$dest"
        ok "settings.json (new)"
        return
    fi

    if diff -q "$settings_tmp" "$dest" >/dev/null 2>&1; then
        ok "settings.json (unchanged)"
        return
    fi

    if [ "$FORCE" = "1" ]; then
        local backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
        cp "$dest" "$backup"
        cp "$settings_tmp" "$dest"
        ok "settings.json (replaced, backup: $backup)"
        return
    fi

    if ! [ -t 0 ]; then
        warn "settings.json differs — use --force to replace"
        return
    fi

    info ""
    info "  Your ~/.claude/settings.json differs from the toolkit version."
    diff --unified=3 "$dest" "$settings_tmp" || true
    info ""
    info "  [k] Keep current  [r] Replace (with backup)  [m] Show paths for manual merge"
    read -r -p "  Choose [k]: " choice
    case "$choice" in
        r|R)
            local backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
            cp "$dest" "$backup"
            cp "$settings_tmp" "$dest"
            ok "settings.json (replaced, backup: $backup)"
            ;;
        m|M)
            info "  Current:  $dest"
            info "  Toolkit:  $settings_tmp"
            ;;
        *)
            ok "settings.json (kept)"
            ;;
    esac
}

# =============================================================================
# PROJECT INSTALL
# =============================================================================

VALID_PROFILES=(terraform databricks fabric)

prompt_profile() {
    if [ -n "$PROFILE" ]; then
        # Validate
        for p in "${VALID_PROFILES[@]}"; do
            [ "$p" = "$PROFILE" ] && return
        done
        err "Invalid profile: $PROFILE (must be one of: ${VALID_PROFILES[*]})"
        exit 1
    fi

    if ! [ -t 0 ]; then
        err "Non-interactive shell. Use --profile to specify platform."
        exit 1
    fi

    info ""
    info "${BOLD}Select platform profile:${RESET}"
    for i in "${!VALID_PROFILES[@]}"; do
        printf "  [%d] %s\n" "$((i + 1))" "${VALID_PROFILES[$i]}"
    done
    info ""
    read -r -p "Profile [1]: " choice
    choice="${choice:-1}"

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#VALID_PROFILES[@]} ] 2>/dev/null; then
        PROFILE="${VALID_PROFILES[$((choice - 1))]}"
    else
        err "Invalid choice"
        exit 1
    fi
}

prompt_client_info() {
    if [ -n "$CLIENT_NAME" ] && [ -n "$CLIENT_PREFIX" ]; then
        return
    fi

    if ! [ -t 0 ]; then
        err "Non-interactive shell. Client info requires interactive mode."
        exit 1
    fi

    info ""
    read -r -p "Client name (e.g., PostNord, KOMBIT): " CLIENT_NAME
    read -r -p "Resource prefix (e.g., pn, kbt): " CLIENT_PREFIX

    if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_PREFIX" ]; then
        err "Client name and prefix are required."
        exit 1
    fi
}

install_project() {
    info ""
    info "${BOLD}=== Project Install ===${RESET}"
    info ""

    # --- Join-mode detection ----------------------------------------
    # If AGENTS.md already exists and carries a toolkit template header,
    # this repo was bootstrapped by Mindflayer already. Switch to
    # "join mode": never touch AGENTS.md, only add agent-specific files
    # the current user is missing. This is the new-teammate path.
    local JOIN_MODE=0
    if [ -f "./AGENTS.md" ] && grep -q '<!-- template:' "./AGENTS.md" 2>/dev/null; then
        JOIN_MODE=1
        info "${BOLD}Detected existing Mindflayer-managed repo${RESET} — join mode."
        info "AGENTS.md will be preserved. Only your agent-specific files will be added."
        info ""
        # Infer profile from AGENTS.md body (the **platform:** line).
        # Before v2.0.0 the template name encoded the platform (e.g. AGENTS-fabric);
        # from v2.0.0 there is a single AGENTS.md template and platform lives in the body.
        # Try the body-line approach first, then fall back to the legacy header for
        # backwards compatibility with v1 repos.
        if [ -z "${PROFILE:-}" ]; then
            local inferred
            inferred="$(sed -n 's/^[[:space:]]*-[[:space:]]*\*\*platform:\*\*[[:space:]]*\([a-z0-9-]*\).*/\1/p' ./AGENTS.md | head -1)"
            if [ -z "$inferred" ]; then
                # Legacy v1 fallback: platform encoded in header comment as AGENTS-<platform>
                inferred="$(sed -n 's/.*template: AGENTS-\([a-z-]*\).*/\1/p' ./AGENTS.md | head -1)"
            fi
            if [ -n "$inferred" ]; then
                PROFILE="$inferred"
                info "  Inferred profile from AGENTS.md: ${BOLD}${PROFILE}${RESET}"
            fi
        fi
    fi

    prompt_profile
    if [ "$JOIN_MODE" != "1" ]; then
        prompt_client_info
    fi

    info ""
    info "Setting up ${BOLD}${CLIENT_NAME}${RESET} (${PROFILE}) repo..."
    info ""

    # --- AGENTS.md ---
    local template_tmp=""
    if [ "$JOIN_MODE" = "1" ]; then
        ok "AGENTS.md (preserved — join mode)"
    else
        template_tmp="$(fetch_to_tmp "templates/AGENTS.md")"

        if [ -f "./AGENTS.md" ] && [ "$FORCE" != "1" ]; then
            # Safe default: preserve existing AGENTS.md unless --force.
            warn "AGENTS.md exists — preserved. Use --force to overwrite."
            template_tmp=""
        fi
    fi

    if [ -n "$template_tmp" ]; then
        # Escape sed special characters in user input to prevent injection
        local safe_name safe_prefix
        safe_name="$(printf '%s' "$CLIENT_NAME" | sed 's/[&/\]/\\&/g')"
        safe_prefix="$(printf '%s' "$CLIENT_PREFIX" | sed 's/[&/\]/\\&/g')"

        # Per-platform repo_type
        local repo_type
        case "$PROFILE" in
            fabric|databricks) repo_type="data-platform" ;;
            terraform)         repo_type="infrastructure" ;;
            *)                 repo_type="unknown" ;;
        esac

        # Per-platform ADR list — injected into {ADR_LIST}
        # Uses a newline-delimited list rendered with awk to avoid sed newline issues.
        local adr_list
        case "$PROFILE" in
            fabric)
                adr_list="- ADR-0012: Fabric Medallion Layers
- ADR-0013: Fabric Semantic Model Design
- ADR-0014: Fabric Git Integration Policy
- ADR-0015: Fabric ADR Triggers"
                ;;
            databricks)
                adr_list="- ADR-0016: Databricks Unity Catalog Structure
- ADR-0017: Databricks Compute Defaults
- ADR-0018: Databricks ADR Triggers"
                ;;
            terraform)
                adr_list="- ADR-0019: Terraform Module Structure
- ADR-0020: Terraform ADR Triggers"
                ;;
            *)
                adr_list="- (no platform ADRs registered for profile '${PROFILE}')"
                ;;
        esac

        # Substitute identity tokens first via sed, then inject ADR list via awk.
        # awk's -v cannot safely carry newlines; write the ADR list to a temp
        # file and have awk splice it in at the {ADR_LIST} marker.
        local adr_list_file
        adr_list_file="$(mktemp)"
        printf '%s\n' "$adr_list" > "$adr_list_file"

        sed "s/{CLIENT_NAME}/${safe_name}/g; s/{PLATFORM}/${PROFILE}/g; s/{REPO_TYPE}/${repo_type}/g; s/{prefix}/${safe_prefix}/g" \
            "$template_tmp" | \
        awk -v listfile="$adr_list_file" '
            BEGIN {
                list = ""
                while ((getline line < listfile) > 0) {
                    list = list (list == "" ? "" : "\n") line
                }
                close(listfile)
            }
            /\{ADR_LIST\}/ { print list; next }
            { print }
        ' > ./AGENTS.md
        rm -f "$adr_list_file"
        ok "AGENTS.md (universal template, profile: ${PROFILE})"
    fi

    # --- Tool-specific project configs ---
    for agent in "${AGENTS_TO_INSTALL[@]}"; do
        case "$agent" in
            claude)
                local settings_tmp
                settings_tmp="$(fetch_to_tmp "settings/claude/settings-${PROFILE}.json")"
                mkdir -p .claude
                safe_copy "$settings_tmp" ".claude/settings.json"
                ;;
            codex)
                local codex_tmp
                codex_tmp="$(fetch_to_tmp "settings/codex/codex.md")"
                safe_copy "$codex_tmp" "./codex.md"
                ;;
            copilot)
                mkdir -p .github
                if [ ! -L ".github/copilot-instructions.md" ]; then
                    ln -sf ../AGENTS.md .github/copilot-instructions.md
                    ok "copilot-instructions.md (symlink to AGENTS.md)"
                else
                    ok "copilot-instructions.md (symlink exists)"
                fi
                ;;
            gemini)
                local gemini_tmp
                gemini_tmp="$(fetch_to_tmp "settings/gemini/gemini.md")"
                safe_copy "$gemini_tmp" "./gemini.md"
                ;;
            cursor)
                mkdir -p .cursor/rules
                local cursor_tmp
                cursor_tmp="$(fetch_to_tmp "settings/cursor/cursor.md")"
                safe_copy "$cursor_tmp" ".cursor/rules/project.md"
                ;;
        esac
    done

    # --- Project directories ---
    mkdir -p docs/adr
    ok "docs/adr/"

    # --- .gitignore ---
    local gitignore_entries=(".claude/settings.local.json" "CLAUDE.local.md")
    for entry in "${gitignore_entries[@]}"; do
        if [ -f .gitignore ] && grep -qF "$entry" .gitignore; then
            continue
        fi
        echo "$entry" >> .gitignore
        ok ".gitignore += $entry"
    done

    # --- Summary ---
    info ""
    if [ "$JOIN_MODE" = "1" ]; then
        info "${BOLD}=== Joined Existing Project ===${RESET}"
    else
        info "${BOLD}=== Project Setup Complete ===${RESET}"
    fi
    info ""
    if [ "$JOIN_MODE" = "1" ]; then
        info "Profile: ${PROFILE} (inferred from AGENTS.md)"
    else
        info "Profile: ${PROFILE} | Client: ${CLIENT_NAME} (${CLIENT_PREFIX})"
    fi
    info ""
    info "Created files:"
    [ -f ./AGENTS.md ] && info "  AGENTS.md"
    [ -f .claude/settings.json ] && info "  .claude/settings.json"
    [ -f ./codex.md ] && info "  codex.md"
    [ -f ./gemini.md ] && info "  gemini.md"
    [ -f .cursor/rules/project.md ] && info "  .cursor/rules/project.md"
    [ -L .github/copilot-instructions.md ] && info "  .github/copilot-instructions.md -> AGENTS.md"
    info "  docs/adr/"
    info ""
    if [ "$JOIN_MODE" != "1" ]; then
        info "${YELLOW}TODO:${RESET} Open AGENTS.md and fill in remaining {placeholders}."
        info ""
    fi

    # --- Template drift check (informational) -----------------------
    if [ -x "$HOME/.ai-toolkit/check-template-update.sh" ] && [ -f ./AGENTS.md ]; then
        info "${BOLD}Template version check:${RESET}"
        bash "$HOME/.ai-toolkit/check-template-update.sh" 2>&1 | sed 's/^/  /' || true
        info ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_args "$@"
    resolve_source

    # If local mode, ensure SCRIPT_DIR is set
    if [ "$LOCAL" = "1" ] && [ -z "${SCRIPT_DIR:-}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    # Remote mode requires curl
    if [ "$LOCAL" != "1" ] && ! command -v curl >/dev/null 2>&1; then
        err "curl is required for remote install. Install curl or use --local."
        exit 1
    fi

    info ""
    info "${BOLD}=== Consultant Toolkit Installer v${VERSION} ===${RESET}"

    detect_agents
    prompt_install_mode
    prompt_agent_selection

    case "$INSTALL_MODE" in
        global)  install_global ;;
        project) install_project ;;
    esac
}

main "$@"

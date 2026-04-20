#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Consultant Toolkit Uninstaller
# Removes files installed by install.sh. Dry-run by default.
#
# Usage:
#   bash ~/.ai-toolkit/uninstall.sh --global              (dry-run: show what would be removed)
#   bash ~/.ai-toolkit/uninstall.sh --global --confirm     (actually remove)
#   bash ~/.ai-toolkit/uninstall.sh --project --confirm    (remove project config from cwd)
#
# Flags:
#   --global    Remove global install (~/.ai-toolkit/, agent configs)
#   --project   Remove project-level config from current directory
#   --confirm   Actually delete files (default is dry-run)
#   --force     Also remove user-modified files (backs up first)
#   --help      Show this help
# =============================================================================

# --- Colors (with fallback for dumb terminals) --------------------------------

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN="" RED="" YELLOW="" RED="" BOLD="" RESET=""
fi

# --- Helpers -----------------------------------------------------------------

info()  { printf "%s\n" "$1"; }
ok()    { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "  %s⚠%s %s\n" "$YELLOW" "$RESET" "$1"; }
err()   { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1"; }

usage() {
    cat <<'USAGE'
Usage: uninstall.sh [OPTIONS]

Options:
  --global    Remove global install (~/.ai-toolkit/, agent configs)
  --project   Remove project-level config from current directory
  --confirm   Actually delete files (default is dry-run)
  --force     Also remove user-modified files (backs up first)
  --help      Show this help

Examples:
  # Preview what would be removed (dry-run)
  bash ~/.ai-toolkit/uninstall.sh --global

  # Actually remove global install
  bash ~/.ai-toolkit/uninstall.sh --global --confirm

  # Remove project config including user-modified files
  bash ~/.ai-toolkit/uninstall.sh --project --confirm --force

USAGE
    exit 0
}

# --- Defaults ----------------------------------------------------------------

MODE=""
CONFIRM=0
FORCE=0

# --- Counters ----------------------------------------------------------------

REMOVED=0
SKIPPED=0
WOULD_REMOVE=0

# --- Parse arguments ---------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --global)
            [ -n "$MODE" ] && { err "--global and --project are mutually exclusive."; exit 1; }
            MODE="global"
            ;;
        --project)
            [ -n "$MODE" ] && { err "--global and --project are mutually exclusive."; exit 1; }
            MODE="project"
            ;;
        --confirm)  CONFIRM=1      ;;
        --force)    FORCE=1        ;;
        --help)     usage          ;;
        *)
            err "Unknown option: $1"
            printf "  Run with --help for usage.\n"
            exit 1
            ;;
    esac
    shift
done

if [ -z "$MODE" ]; then
    err "Must specify --global or --project."
    printf "  Run with --help for usage.\n"
    exit 1
fi

# --- Core removal helpers ----------------------------------------------------

# remove_file "$path" ["user-modified"]
#   Removes a single file. If the second argument is "user-modified", the file
#   is only removed when --force is set; otherwise it is skipped.
remove_file() {
    local path="$1"
    local guarded="${2:-}"
    local display="${path/#$HOME/~}"

    [ ! -f "$path" ] && return

    # User-modified files require --force
    if [ "$guarded" = "user-modified" ] && [ "$FORCE" -eq 0 ]; then
        if [ "$CONFIRM" -eq 1 ]; then
            err "$display (skipped — user-modified, use --force)"
        else
            printf "  would skip:   %s (user-modified, use --force)\n" "$display"
        fi
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    if [ "$CONFIRM" -eq 0 ]; then
        printf "  would remove: %s\n" "$display"
        WOULD_REMOVE=$((WOULD_REMOVE + 1))
        return
    fi

    # --force on guarded files: back up first
    if [ "$guarded" = "user-modified" ] && [ "$FORCE" -eq 1 ]; then
        cp "$path" "${path}.bak"
    fi

    rm -f "$path"
    ok "$display"
    REMOVED=$((REMOVED + 1))
}

# remove_dir "$path"
#   Removes a directory recursively.
remove_dir() {
    local path="$1"
    local display="${path/#$HOME/~}"

    [ ! -d "$path" ] && return

    if [ "$CONFIRM" -eq 0 ]; then
        printf "  would remove: %s (entire directory)\n" "$display"
        WOULD_REMOVE=$((WOULD_REMOVE + 1))
        return
    fi

    rm -rf "$path"
    ok "$display"
    REMOVED=$((REMOVED + 1))
}

# remove_if_toolkit_skill "$path"
#   Removes a skill directory if it contains a SKILL.md (i.e. toolkit-managed).
remove_if_toolkit_skill() {
    local path="$1"
    local display="${path/#$HOME/~}"

    [ ! -d "$path" ] && return

    if [ ! -f "$path/SKILL.md" ]; then
        return
    fi

    if [ "$CONFIRM" -eq 0 ]; then
        printf "  would remove: %s\n" "$display"
        WOULD_REMOVE=$((WOULD_REMOVE + 1))
        return
    fi

    rm -rf "$path"
    ok "$display"
    REMOVED=$((REMOVED + 1))
}

# remove_symlink "$path" "$expected_target"
#   Removes a symlink only if it points to the expected target.
remove_symlink() {
    local path="$1"
    local expected_target="$2"
    local display="$path"

    [ ! -L "$path" ] && return

    local actual_target
    actual_target="$(readlink "$path")"

    if [ "$actual_target" != "$expected_target" ]; then
        return
    fi

    if [ "$CONFIRM" -eq 0 ]; then
        printf "  would remove: %s (symlink → %s)\n" "$display" "$expected_target"
        WOULD_REMOVE=$((WOULD_REMOVE + 1))
        return
    fi

    rm -f "$path"
    ok "$display (symlink)"
    REMOVED=$((REMOVED + 1))
}

# --- Global uninstall --------------------------------------------------------

uninstall_global() {
    if [ "$CONFIRM" -eq 1 ]; then
        printf "%s=== Consultant Toolkit Uninstaller ===%s\n\n" "$BOLD" "$RESET"
        printf "Global uninstall:\n\n"
    else
        printf "%s=== Consultant Toolkit Uninstaller (dry-run) ===%s\n\n" "$BOLD" "$RESET"
        printf "Global uninstall preview:\n\n"
    fi

    # 1. ~/.ai-toolkit/ — entire directory
    remove_dir "$HOME/.ai-toolkit"

    # 2. Claude skills (toolkit-managed only)
    local TOOLKIT_SKILLS="adr branch-cleanup kimball-model promote-adr setup-repo smart-commit smart-pr terraform-scaffold"
    for skill in $TOOLKIT_SKILLS; do
        remove_if_toolkit_skill "$HOME/.claude/skills/$skill"
    done

    # 3. Claude config files (user-modified)
    remove_file "$HOME/.claude/CLAUDE.md" "user-modified"
    remove_file "$HOME/.claude/settings.json" "user-modified"

    # 4. Other agent configs (toolkit-created, safe to remove)
    remove_file "$HOME/.codex/AGENTS.md"
    remove_file "$HOME/.gemini/GEMINI.md"
    remove_file "$HOME/.cursor/rules.md"
    remove_file "$HOME/.copilot/copilot-instructions.md"
}

# --- Project uninstall -------------------------------------------------------

uninstall_project() {
    if [ "$CONFIRM" -eq 1 ]; then
        printf "%s=== Consultant Toolkit Uninstaller ===%s\n\n" "$BOLD" "$RESET"
        printf "Project uninstall (%s):\n\n" "$(pwd)"
    else
        printf "%s=== Consultant Toolkit Uninstaller (dry-run) ===%s\n\n" "$BOLD" "$RESET"
        printf "Project uninstall preview (%s):\n\n" "$(pwd)"
    fi

    # AGENTS.md — user fills in placeholders, so treat as user-modified
    remove_file "AGENTS.md" "user-modified"

    # Tool-specific configs (generated, safe to remove)
    remove_file ".claude/settings.json"
    remove_file "codex.md"
    remove_file "gemini.md"
    remove_file ".cursor/rules/project.md"

    # Copilot symlink — only remove if it points to ../AGENTS.md
    remove_symlink ".github/copilot-instructions.md" "../AGENTS.md"
}

# --- Main --------------------------------------------------------------------

if [ "$MODE" = "global" ]; then
    uninstall_global
elif [ "$MODE" = "project" ]; then
    uninstall_project
fi

# --- Summary -----------------------------------------------------------------

printf "\n"

if [ "$CONFIRM" -eq 0 ]; then
    printf "Would remove %d item%s" "$WOULD_REMOVE" "$([ "$WOULD_REMOVE" -ne 1 ] && printf "s" || true)"
    if [ "$SKIPPED" -gt 0 ]; then
        printf ", skip %d item%s" "$SKIPPED" "$([ "$SKIPPED" -ne 1 ] && printf "s" || true)"
    fi
    printf ".\n"

    if [ "$WOULD_REMOVE" -gt 0 ]; then
        printf "Re-run with --confirm to actually remove files.\n"
    fi
    if [ "$SKIPPED" -gt 0 ]; then
        printf "Re-run with --confirm --force to also remove user-modified files.\n"
    fi
else
    printf "Removed %d item%s" "$REMOVED" "$([ "$REMOVED" -ne 1 ] && printf "s" || true)"
    if [ "$SKIPPED" -gt 0 ]; then
        printf ", skipped %d item%s" "$SKIPPED" "$([ "$SKIPPED" -ne 1 ] && printf "s" || true)"
    fi
    printf ".\n"
fi

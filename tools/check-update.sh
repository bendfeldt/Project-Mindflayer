#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Check if the installed Consultant Toolkit has updates available.
# Compares ~/.ai-toolkit/version against the latest GitHub release.
# Reports only — never downloads or modifies files.
#
# Usage:
#   bash ~/.ai-toolkit/check-update.sh
#   GITHUB_TOKEN=ghp_... bash ~/.ai-toolkit/check-update.sh   (avoids rate limits)
#
# To update:
#   bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global --force
# =============================================================================

# --- Colors (with fallback for dumb terminals) --------------------------------

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN="" YELLOW="" RED="" BOLD="" RESET=""
fi

# --- Require curl ------------------------------------------------------------

if ! command -v curl >/dev/null 2>&1; then
    printf "  %s✗%s curl is required but not installed.\n" "$RED" "$RESET"
    exit 1
fi

# --- Read installed version --------------------------------------------------

VERSION_FILE="$HOME/.ai-toolkit/version"

if [ ! -f "$VERSION_FILE" ]; then
    printf "  %s✗%s Version file not found: %s\n" "$RED" "$RESET" "$VERSION_FILE"
    printf "  Run the installer first to create an initial install.\n"
    exit 1
fi

INSTALLED="$(cat "$VERSION_FILE" 2>/dev/null || true)"

if [ -z "$INSTALLED" ]; then
    printf "  %s✗%s Version file is empty: %s\n" "$RED" "$RESET" "$VERSION_FILE"
    exit 1
fi

# --- Semver comparison -------------------------------------------------------

# Compares two semver strings. Returns 0 (true) if $1 > $2.
# Strips leading 'v' and compares major.minor.patch arithmetically.
version_gt() {
    local a="${1#v}"
    local b="${2#v}"

    local a_major a_minor a_patch
    local b_major b_minor b_patch

    a_major="$(printf "%s" "$a" | cut -d. -f1)"
    a_minor="$(printf "%s" "$a" | cut -d. -f2)"
    a_patch="$(printf "%s" "$a" | cut -d. -f3)"

    b_major="$(printf "%s" "$b" | cut -d. -f1)"
    b_minor="$(printf "%s" "$b" | cut -d. -f2)"
    b_patch="$(printf "%s" "$b" | cut -d. -f3)"

    # Default missing components to 0
    a_major="${a_major:-0}"; a_minor="${a_minor:-0}"; a_patch="${a_patch:-0}"
    b_major="${b_major:-0}"; b_minor="${b_minor:-0}"; b_patch="${b_patch:-0}"

    if [ "$a_major" -gt "$b_major" ] 2>/dev/null; then return 0; fi
    if [ "$a_major" -lt "$b_major" ] 2>/dev/null; then return 1; fi
    if [ "$a_minor" -gt "$b_minor" ] 2>/dev/null; then return 0; fi
    if [ "$a_minor" -lt "$b_minor" ] 2>/dev/null; then return 1; fi
    if [ "$a_patch" -gt "$b_patch" ] 2>/dev/null; then return 0; fi
    return 1
}

# --- GitHub API: latest release tag ------------------------------------------

github_latest_release() {
    local repo="$1"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local response=""

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        # Pass token via --config stdin to avoid token appearing in process listings (ps aux)
        response="$(printf 'header = "Authorization: Bearer %s"\n' "${GITHUB_TOKEN}" \
            | curl -sfL --proto =https --config - "$api_url" 2>/dev/null || true)"
    else
        response="$(curl -sfL --proto =https "$api_url" 2>/dev/null || true)"
    fi

    [ -z "$response" ] && return

    # Extract tag_name without jq — POSIX sed, no -P flag
    printf "%s" "$response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

# --- Main --------------------------------------------------------------------

REPO="bendfeldt/Project-Mindflayer"
UPDATE_CMD='bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global --force'

printf "%s=== Consultant Toolkit Update Check ===%s\n\n" "$BOLD" "$RESET"

LATEST="$(github_latest_release "$REPO")"

if [ -z "$LATEST" ]; then
    printf "  %s✗%s Could not fetch release info (network error or API rate limit)\n" "$RED" "$RESET"
    printf "    Tip: set GITHUB_TOKEN env var for higher rate limits\n"
    exit 1
fi

# Strip leading 'v' for display consistency
INSTALLED_DISPLAY="${INSTALLED#v}"
LATEST_DISPLAY="${LATEST#v}"

printf "  Installed:  %s\n" "$INSTALLED_DISPLAY"
printf "  Latest:     %s\n\n" "$LATEST_DISPLAY"

if [ "$INSTALLED_DISPLAY" = "$LATEST_DISPLAY" ]; then
    printf "  %s✓%s Up to date.\n" "$GREEN" "$RESET"
elif version_gt "$LATEST" "$INSTALLED"; then
    printf "  %s⚠%s Update available!\n\n" "$YELLOW" "$RESET"
    printf "  To update:\n"
    printf "    %s\n" "$UPDATE_CMD"
else
    # Installed is newer than latest release (dev build or pre-release)
    printf "  %s✓%s Up to date (installed version is ahead of latest release).\n" "$GREEN" "$RESET"
fi

#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Check external stores for new releases.
# Reads ~/.ai-toolkit/stores.yml (or ./stores.yml if running from the repo).
# Reports drift — never downloads or writes to files.
#
# Usage:
#   bash ~/.ai-toolkit/check-stores.sh
#   GITHUB_TOKEN=ghp_... bash ~/.ai-toolkit/check-stores.sh   (avoids rate limits)
#
# To acknowledge a new version:
#   Edit stores.yml and bump known_version, then review the release manually.
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

# --- Locate stores.yml -------------------------------------------------------

STORES_FILE=""
if [ -f "$HOME/.ai-toolkit/stores.yml" ]; then
    STORES_FILE="$HOME/.ai-toolkit/stores.yml"
elif [ -f "./stores.yml" ]; then
    STORES_FILE="./stores.yml"
else
    printf "  %s✗%s stores.yml not found.\n" "$RED" "$RESET"
    printf "  Run: bash install.sh --global --local  (from the toolkit repo)\n"
    exit 1
fi

# --- Require curl ------------------------------------------------------------

if ! command -v curl >/dev/null 2>&1; then
    printf "  %s✗%s curl is required but not installed.\n" "$RED" "$RESET"
    exit 1
fi

# --- Parse stores.yml with awk (no yq/jq required) ---------------------------

parse_stores() {
    awk '
        /^  - id:/          { if (id != "") print id "|" repo "|" stype "|" known
                               id = $NF; repo = ""; stype = ""; known = "" }
        /^    repo:/         { repo = $NF }
        /^    type:/         { stype = $NF }
        /^    known_version:/ { known = $NF }
        END                  { if (id != "") print id "|" repo "|" stype "|" known }
    ' "$STORES_FILE"
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

UP_TO_DATE=0
UPDATES=0
ERRORS=0

printf "%s=== External Stores ===%s\n" "$BOLD" "$RESET"
printf "Registry: %s\n\n" "$STORES_FILE"

while IFS='|' read -r id repo stype known; do
    [ -z "$id" ] && continue

    printf "  %s%s%s  (%s)\n" "$BOLD" "$id" "$RESET" "$repo"

    if [ "$stype" != "releases" ]; then
        printf "  %s⚠%s Unsupported type '%s' — only 'releases' is supported\n\n" "$YELLOW" "$RESET" "$stype"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    LATEST="$(github_latest_release "$repo")"

    if [ -z "$LATEST" ]; then
        printf "  %s⚠%s Could not fetch release info (network error or API rate limit)\n" "$YELLOW" "$RESET"
        printf "    Tip: set GITHUB_TOKEN env var for higher rate limits\n\n"
        ERRORS=$((ERRORS + 1))
    elif [ "$LATEST" = "$known" ]; then
        printf "  %s✓%s Up to date (%s)\n\n" "$GREEN" "$RESET" "$known"
        UP_TO_DATE=$((UP_TO_DATE + 1))
    else
        printf "  %s⚠%s New release available: %s  (you have %s)\n" "$YELLOW" "$RESET" "$LATEST" "$known"
        printf "    https://github.com/%s/releases/tag/%s\n\n" "$repo" "$LATEST"
        UPDATES=$((UPDATES + 1))
    fi

done < <(parse_stores)

# --- Summary -----------------------------------------------------------------

printf "%s=== Summary ===%s\n" "$BOLD" "$RESET"
printf "  Up to date:    %d\n" "$UP_TO_DATE"
printf "  Updates found: %d\n" "$UPDATES"
if [ "$ERRORS" -gt 0 ]; then
    printf "  Errors:        %d\n" "$ERRORS"
fi

if [ "$UPDATES" -gt 0 ]; then
    printf "\nTo acknowledge: edit %s and update known_version.\n" "$STORES_FILE"
fi

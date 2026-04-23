#!/usr/bin/env bash
# Refresh ./.claude/skills/ from the toolkit source at ~/.ai-toolkit/skills/.
# Use when `tools/check-skills-update.sh` reports STALE skills.
#
# Usage:
#   tools/sync-skills.sh                 # refresh stale + identical
#   tools/sync-skills.sh --dry-run       # show what would change
#   tools/sync-skills.sh --force         # overwrite AHEAD/edited skills too (destructive)

set -euo pipefail

TOOLKIT_SKILLS="$HOME/.ai-toolkit/skills"
REPO_SKILLS="./.claude/skills"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN="" ; YELLOW="" ; RED="" ; BOLD="" ; RESET=""
fi

if [ ! -d "$TOOLKIT_SKILLS" ]; then
    echo "${RED}Toolkit source not found: $TOOLKIT_SKILLS${RESET}"
    echo "Run \`install.sh --global\` first."
    exit 1
fi

mkdir -p "$REPO_SKILLS"

skill_version() {
    awk '/^---$/{c++; next} c==1 && /^version:/{print $2; exit}' "$1" 2>/dev/null || true
}

refreshed=0
added=0
skipped_ahead=0

printf '%sSync skills from toolkit%s%s\n\n' "$BOLD" "$RESET" "$([ $DRY_RUN -eq 1 ] && echo ' (DRY RUN)')"

for toolkit_dir in "$TOOLKIT_SKILLS"/*/; do
    [ -d "$toolkit_dir" ] || continue
    name="$(basename "$toolkit_dir")"
    toolkit_file="$toolkit_dir/SKILL.md"
    [ -f "$toolkit_file" ] || continue

    repo_dir="$REPO_SKILLS/$name"
    repo_file="$repo_dir/SKILL.md"

    toolkit_v="$(skill_version "$toolkit_file")"
    toolkit_v="${toolkit_v:-unknown}"

    if [ ! -f "$repo_file" ]; then
        # New skill from toolkit
        if [ $DRY_RUN -eq 1 ]; then
            printf '  + %-22s (new, v%s)\n' "$name" "$toolkit_v"
        else
            mkdir -p "$repo_dir"
            cp -R "$toolkit_dir." "$repo_dir/"
            printf '  %s+ %-22s (new, v%s)%s\n' "$GREEN" "$name" "$toolkit_v" "$RESET"
        fi
        added=$((added + 1))
        continue
    fi

    repo_v="$(skill_version "$repo_file")"
    repo_v="${repo_v:-unknown}"

    # Content identical — nothing to do
    if diff -qr "$toolkit_dir" "$repo_dir" >/dev/null 2>&1; then
        continue
    fi

    # Determine direction
    newest="$(printf '%s\n%s\n' "$repo_v" "$toolkit_v" | sort -V | tail -1)"
    if [ "$repo_v" = "$toolkit_v" ] || [ "$newest" = "$toolkit_v" ]; then
        # Toolkit wins (same version with content diff → toolkit is canonical;
        # or toolkit version is strictly newer)
        if [ $DRY_RUN -eq 1 ]; then
            printf '  ~ %-22s (%s → %s)\n' "$name" "$repo_v" "$toolkit_v"
        else
            rm -rf "$repo_dir"
            mkdir -p "$repo_dir"
            cp -R "$toolkit_dir." "$repo_dir/"
            printf '  %s~ %-22s (%s → %s)%s\n' "$YELLOW" "$name" "$repo_v" "$toolkit_v" "$RESET"
        fi
        refreshed=$((refreshed + 1))
    else
        # Repo is ahead
        if [ $FORCE -eq 1 ]; then
            if [ $DRY_RUN -eq 1 ]; then
                printf '  ! %-22s (FORCE: %s → %s, destructive)\n' "$name" "$repo_v" "$toolkit_v"
            else
                rm -rf "$repo_dir"
                mkdir -p "$repo_dir"
                cp -R "$toolkit_dir." "$repo_dir/"
                printf '  %s! %-22s (FORCE: %s → %s)%s\n' "$RED" "$name" "$repo_v" "$toolkit_v" "$RESET"
            fi
            refreshed=$((refreshed + 1))
        else
            printf '  %s. %-22s (skipped, repo ahead %s > toolkit %s)%s\n' \
                "$YELLOW" "$name" "$repo_v" "$toolkit_v" "$RESET"
            skipped_ahead=$((skipped_ahead + 1))
        fi
    fi
done

echo ""
printf 'Refreshed: %d  Added: %d  Skipped (ahead): %d\n' \
    "$refreshed" "$added" "$skipped_ahead"

if [ $skipped_ahead -gt 0 ] && [ $FORCE -eq 0 ]; then
    echo ""
    echo "${YELLOW}Some repo skills are ahead of the toolkit.${RESET}"
    echo "  To promote local changes upstream: /promote-skill"
    echo "  To overwrite local changes:        tools/sync-skills.sh --force"
fi

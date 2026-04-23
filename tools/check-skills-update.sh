#!/usr/bin/env bash
# Check if skills in the current repo's ./.claude/skills/ have drifted from the
# toolkit source at ~/.ai-toolkit/skills/. Run from a repo root with
# ./.claude/skills/ laid down by `install.sh --project --tools claude`.
#
# Mirrors tools/check-template-update.sh.

set -euo pipefail

TOOLKIT_SKILLS="$HOME/.ai-toolkit/skills"
REPO_SKILLS="./.claude/skills"

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN="" ; YELLOW="" ; RED="" ; BOLD="" ; RESET=""
fi

if [ ! -d "$REPO_SKILLS" ]; then
    echo "No ./.claude/skills/ in current directory."
    echo "Run \`install.sh --project --tools claude\` first."
    exit 1
fi

if [ ! -d "$TOOLKIT_SKILLS" ]; then
    echo "${RED}Toolkit source not found: $TOOLKIT_SKILLS${RESET}"
    echo "Run \`install.sh --global\` first."
    exit 1
fi

# Extract a `version:` field from a SKILL.md's YAML frontmatter.
# Prints the version string, or "unknown" if missing.
skill_version() {
    local file="$1"
    local v
    v=$(awk '/^---$/{c++; next} c==1 && /^version:/{print $2; exit}' "$file" 2>/dev/null || true)
    [ -z "$v" ] && v="unknown"
    printf '%s' "$v"
}

stale=0
ahead=0
matched=0
missing_in_toolkit=0

printf '%sSkill drift check:%s\n\n' "$BOLD" "$RESET"
printf '%-22s  %-10s  %-10s  %s\n' "SKILL" "REPO" "TOOLKIT" "STATUS"
printf '%-22s  %-10s  %-10s  %s\n' "----------------------" "----------" "----------" "----------------"

for repo_skill in "$REPO_SKILLS"/*/SKILL.md; do
    [ -f "$repo_skill" ] || continue
    name="$(basename "$(dirname "$repo_skill")")"
    toolkit_skill="$TOOLKIT_SKILLS/$name/SKILL.md"

    repo_v="$(skill_version "$repo_skill")"

    if [ ! -f "$toolkit_skill" ]; then
        printf '%-22s  %-10s  %-10s  %sLOCAL-ONLY%s\n' \
            "$name" "$repo_v" "—" "$YELLOW" "$RESET"
        missing_in_toolkit=$((missing_in_toolkit + 1))
        continue
    fi

    toolkit_v="$(skill_version "$toolkit_skill")"

    if [ "$repo_v" = "$toolkit_v" ]; then
        # Versions equal — compare content to detect unversioned edits
        if diff -q "$repo_skill" "$toolkit_skill" >/dev/null 2>&1; then
            printf '%-22s  %-10s  %-10s  %s✓ in sync%s\n' \
                "$name" "$repo_v" "$toolkit_v" "$GREEN" "$RESET"
            matched=$((matched + 1))
        else
            printf '%-22s  %-10s  %-10s  %sEDITED (same version)%s\n' \
                "$name" "$repo_v" "$toolkit_v" "$YELLOW" "$RESET"
            stale=$((stale + 1))
        fi
    else
        # Version mismatch — decide direction lexicographically
        if [ "$(printf '%s\n%s\n' "$repo_v" "$toolkit_v" | sort -V | tail -1)" = "$toolkit_v" ]; then
            printf '%-22s  %-10s  %-10s  %sSTALE (toolkit ahead)%s\n' \
                "$name" "$repo_v" "$toolkit_v" "$YELLOW" "$RESET"
            stale=$((stale + 1))
        else
            printf '%-22s  %-10s  %-10s  %sAHEAD (repo ahead)%s\n' \
                "$name" "$repo_v" "$toolkit_v" "$YELLOW" "$RESET"
            ahead=$((ahead + 1))
        fi
    fi
done

echo ""
printf 'In sync: %d  Stale: %d  Ahead: %d  Local-only: %d\n' \
    "$matched" "$stale" "$ahead" "$missing_in_toolkit"
echo ""

if [ "$stale" -gt 0 ]; then
    echo "${YELLOW}⚠ Some skills are behind the toolkit.${RESET}"
    echo "  Refresh with: tools/sync-skills.sh"
    echo "  Or re-run:    install.sh --project --tools claude --force"
fi

if [ "$ahead" -gt 0 ]; then
    echo "${YELLOW}⚠ Some skills are ahead of the toolkit (edited locally).${RESET}"
    echo "  Promote with: /promote-skill"
fi

if [ "$missing_in_toolkit" -gt 0 ]; then
    echo "${YELLOW}ℹ Local-only skills exist.${RESET}"
    echo "  If broadly applicable, promote with: /promote-skill"
fi

if [ "$stale" -eq 0 ] && [ "$ahead" -eq 0 ] && [ "$missing_in_toolkit" -eq 0 ]; then
    echo "${GREEN}✓ All skills in sync with the toolkit.${RESET}"
fi

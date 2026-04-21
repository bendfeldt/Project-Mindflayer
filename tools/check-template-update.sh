#!/usr/bin/env bash
# Check if the current repo's AGENTS.md has drifted from its template.
# Run from any repo root that has an AGENTS.md (or legacy CLAUDE.md) with a template version header.

set -euo pipefail

TEMPLATE_DIR="$HOME/.ai-toolkit/templates"

# Colors via tput with fallback for dumb terminals
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
else
    GREEN=""
    YELLOW=""
    RESET=""
fi

# Find the repo instruction file — prefer AGENTS.md, fall back to CLAUDE.md
if [ -f "./AGENTS.md" ]; then
    REPO_FILE="./AGENTS.md"
elif [ -f "./CLAUDE.md" ]; then
    REPO_FILE="./CLAUDE.md"
    echo "Note: This repo uses CLAUDE.md (legacy). Consider renaming to AGENTS.md for cross-tool compatibility."
    echo ""
else
    echo "No AGENTS.md or CLAUDE.md found in current directory."
    exit 1
fi

# Extract template name from header comment (POSIX-compatible, no grep -P)
TEMPLATE_NAME=$(sed -n 's/.*template: \([^ |]*\).*/\1/p' "$REPO_FILE" | head -1)
REPO_VERSION=$(sed -n 's/.*version: \([^ |]*\).*/\1/p' "$REPO_FILE" | head -1)

if [ -z "$TEMPLATE_NAME" ]; then
    echo "No Mindflayer template header detected — skipping drift check."
    exit 0
fi

# Check for legacy v1 templates (platform-specific)
case "$TEMPLATE_NAME" in
    AGENTS-fabric|AGENTS-databricks|AGENTS-terraform)
        echo "${YELLOW}⚠ Legacy v1 template detected: $TEMPLATE_NAME${RESET}"
        echo ""
        echo "Mindflayer v2 unifies all platforms into a single AGENTS.md;"
        echo "platform conventions moved to ADRs."
        echo ""
        echo "To migrate to v2, re-run:"
        echo "  /setup-repo"
        echo "or:"
        echo "  install.sh --project --force --profile <platform>"
        echo ""
        exit 0
        ;;
    AGENTS)
        # v2 template — proceed with normal drift check
        ;;
    *)
        echo "Unknown template name: $TEMPLATE_NAME"
        exit 1
        ;;
esac

TEMPLATE_FILE="$TEMPLATE_DIR/${TEMPLATE_NAME}.md"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template not found: $TEMPLATE_FILE"
    exit 1
fi

TEMPLATE_VERSION=$(sed -n 's/.*version: \([^ |]*\).*/\1/p' "$TEMPLATE_FILE" | head -1)

echo "Repo file: $REPO_FILE"
echo "  Template:  $TEMPLATE_NAME"
echo "  Version:   $REPO_VERSION"
echo ""
echo "Current template:"
echo "  Location:  $TEMPLATE_FILE"
echo "  Version:   $TEMPLATE_VERSION"
echo ""

if [ "$REPO_VERSION" = "$TEMPLATE_VERSION" ]; then
    echo "${GREEN}✓ Versions match. No structural template updates available.${RESET}"
else
    echo "${YELLOW}⚠ Template has been updated ($REPO_VERSION → $TEMPLATE_VERSION).${RESET}"
    echo ""
    echo "Structural diff (ignoring filled-in values is up to you):"
    echo "---"
    diff --unified=3 "$REPO_FILE" "$TEMPLATE_FILE" || true
    echo "---"
    echo ""
    echo "Review the diff above. New sections or ADR triggers from the template"
    echo "may be worth adding. Client-specific values (prefix, subscription, etc.)"
    echo "are expected to differ."
fi

#!/usr/bin/env bash
# Check if the current repo's AGENTS.md has drifted from its template.
# Run from any repo root that has an AGENTS.md (or legacy CLAUDE.md) with a template version header.

set -euo pipefail

TEMPLATE_DIR="$HOME/.claude/docs/repo-templates"

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
    echo "No template header found in $REPO_FILE."
    echo "This file may not have been created from a template."
    exit 1
fi

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
    echo "✓ Versions match. No structural template updates available."
else
    echo "⚠ Template has been updated ($REPO_VERSION → $TEMPLATE_VERSION)."
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

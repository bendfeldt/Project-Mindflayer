#!/usr/bin/env bash
# Sync your global agent config from ~/.claude/CLAUDE.md to all tool locations.
# Run this after editing ~/.claude/CLAUDE.md to push changes to Codex, Gemini, etc.

set -euo pipefail

SOURCE="$HOME/.claude/CLAUDE.md"

if [ ! -f "$SOURCE" ]; then
    echo "Source not found: $SOURCE"
    echo "Run install.sh first."
    exit 1
fi

# Claude Code — already the source
echo "Source: ~/.claude/CLAUDE.md"

# Codex CLI
mkdir -p ~/.codex
cp "$SOURCE" ~/.codex/AGENTS.md
echo "Synced: ~/.codex/AGENTS.md"

# Gemini CLI
mkdir -p ~/.gemini
cp "$SOURCE" ~/.gemini/GEMINI.md
echo "Synced: ~/.gemini/GEMINI.md"

# Cursor
if [ -d ~/.cursor ]; then
    cp "$SOURCE" ~/.cursor/rules.md
    echo "Synced: ~/.cursor/rules.md"
fi

# GitHub Copilot CLI
mkdir -p ~/.copilot
cp "$SOURCE" ~/.copilot/copilot-instructions.md
echo "Synced: ~/.copilot/copilot-instructions.md"

echo ""
echo "All agent tools updated."

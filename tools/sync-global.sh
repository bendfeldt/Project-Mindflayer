#!/usr/bin/env bash
# Copy the global baseline to each agent's config directory.
# Source of truth: ~/.ai-toolkit/AGENTS.md

set -euo pipefail

TOOLKIT_HOME="$HOME/.ai-toolkit"
BASELINE="$TOOLKIT_HOME/AGENTS.md"

if [ ! -f "$BASELINE" ]; then
    echo "Baseline not found: $BASELINE"
    echo "Run install.sh --global first."
    exit 1
fi

echo "Source: $BASELINE"

# Claude Code
mkdir -p "$HOME/.claude"
cp "$BASELINE" "$HOME/.claude/CLAUDE.md"
echo "Synced: ~/.claude/CLAUDE.md"

# Codex CLI
mkdir -p "$HOME/.codex"
cp "$BASELINE" "$HOME/.codex/AGENTS.md"
echo "Synced: ~/.codex/AGENTS.md"

# Gemini CLI
mkdir -p "$HOME/.gemini"
cp "$BASELINE" "$HOME/.gemini/GEMINI.md"
echo "Synced: ~/.gemini/GEMINI.md"

# Cursor — only if already present
if [ -d "$HOME/.cursor" ]; then
    cp "$BASELINE" "$HOME/.cursor/rules.md"
    echo "Synced: ~/.cursor/rules.md"
fi

# GitHub Copilot CLI
mkdir -p "$HOME/.copilot"
cp "$BASELINE" "$HOME/.copilot/copilot-instructions.md"
echo "Synced: ~/.copilot/copilot-instructions.md"

echo ""
echo "All agent configs synced from baseline."

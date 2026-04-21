#!/usr/bin/env bash
# Regenerate each agent's global config as concat(baseline, personal).
# Run after editing ~/.ai-toolkit/AGENTS.personal.md.

set -euo pipefail

TOOLKIT_HOME="$HOME/.ai-toolkit"
BASELINE="$TOOLKIT_HOME/AGENTS.md"
PERSONAL="$TOOLKIT_HOME/AGENTS.personal.md"

if [ ! -f "$BASELINE" ]; then
    echo "Baseline not found: $BASELINE"
    echo "Run install.sh --global first."
    exit 1
fi

if [ ! -f "$PERSONAL" ]; then
    echo "Personal overlay not found: $PERSONAL"
    echo "Run install.sh --global to seed it from the example."
    exit 1
fi

COMBINED="$(mktemp)"
trap 'rm -f "$COMBINED"' EXIT

cat "$BASELINE" > "$COMBINED"
printf '\n\n' >> "$COMBINED"
cat "$PERSONAL" >> "$COMBINED"

echo "Source: $BASELINE + $PERSONAL"

write_config() {
    local dir="$1" name="$2"
    if [ ! -d "$dir" ]; then
        return
    fi
    cp "$COMBINED" "$dir/$name"
    echo "Synced: $dir/$name"
}

# Claude Code
mkdir -p "$HOME/.claude"
cp "$COMBINED" "$HOME/.claude/CLAUDE.md"
echo "Synced: ~/.claude/CLAUDE.md"

# Codex CLI
mkdir -p "$HOME/.codex"
cp "$COMBINED" "$HOME/.codex/AGENTS.md"
echo "Synced: ~/.codex/AGENTS.md"

# Gemini CLI
mkdir -p "$HOME/.gemini"
cp "$COMBINED" "$HOME/.gemini/GEMINI.md"
echo "Synced: ~/.gemini/GEMINI.md"

# Cursor — only if already present
if [ -d "$HOME/.cursor" ]; then
    cp "$COMBINED" "$HOME/.cursor/rules.md"
    echo "Synced: ~/.cursor/rules.md"
fi

# GitHub Copilot CLI
mkdir -p "$HOME/.copilot"
cp "$COMBINED" "$HOME/.copilot/copilot-instructions.md"
echo "Synced: ~/.copilot/copilot-instructions.md"

echo ""
echo "All agent configs regenerated from baseline + personal."

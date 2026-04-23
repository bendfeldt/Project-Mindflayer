# .claude/hooks/

Event-driven shell scripts that run before or after Claude Code tool use.

## Purpose

Hooks are **guardrails**. They automate validation, linting, formatting, and
can block unsafe operations entirely. Unlike `.claude/settings.json` permission
rules (which declaratively allow/deny commands), hooks run arbitrary logic.

## Relationship to `.claude/settings.json`

- `settings.json` — **declarative** permission allow/deny lists
- `hooks/*.sh` — **imperative** validation and side-effects

Most safety guardrails in this toolkit are expressed in `settings.json` (per
profile). Use hooks for things that need logic (e.g., "lint only staged files",
"reject commits that touch both infra and code").

## Common hook types

- `PreToolUse` — validate or block before a tool runs
- `PostToolUse` — format, lint, or log after a tool runs
- `SessionStart` — run at session boot (useful for Cowork cloud-VM setup)

## Example

`validate-bash.sh` — refuse bash commands with dangerous patterns:

```bash
#!/usr/bin/env bash
set -euo pipefail
cmd="${CLAUDE_TOOL_INPUT_command:-}"
case "$cmd" in
  *"rm -rf /"*|*"curl | sh"*) echo "BLOCKED: $cmd" >&2; exit 2 ;;
esac
```

Register it in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash.sh" }] }
    ]
  }
}
```

## Scope

This folder is **client-specific**. The Mindflayer toolkit does not ship
hooks by default; safety is expressed declaratively in `settings.json`. Add
hooks when declarative rules can't express the intent.

## References

- Claude Code — Hooks: https://docs.claude.com/en/docs/claude-code/hooks

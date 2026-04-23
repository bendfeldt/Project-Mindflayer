# .claude/agents/

Specialized sub-agents with isolated context and role-specific tools.

## Purpose

Sub-agents let Claude delegate focused tasks to dedicated personas (code
reviewer, security auditor, test generator) without polluting the main
conversation's context. Each sub-agent:

- Runs in its own context window
- Has its own tool allowlist
- May use a different model (e.g., faster/cheaper for triage)

## Conventions

- One `.md` file per sub-agent. The filename (without `.md`) is the agent name.
- Frontmatter defines role, tools, model, and auto-invocation conditions.

## Example

```markdown
---
name: code-reviewer
description: Review diffs for correctness, security, and style issues
tools: [Read, Grep, Glob]
model: claude-sonnet-4.6
---

You are a senior reviewer. Read the diff, raise only high-signal findings.
Never modify code.
```

## Scope

This folder is **client-specific**. The Mindflayer toolkit does not ship
sub-agents. Add them as the engagement identifies recurring narrow tasks
that benefit from isolation.

## References

- Claude Code — Subagents: https://docs.claude.com/en/docs/claude-code/subagents

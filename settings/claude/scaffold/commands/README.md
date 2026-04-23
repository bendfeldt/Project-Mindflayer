# .claude/commands/

Custom slash commands exposed to Claude Code as `/project:<name>`.

## Purpose

Commands capture **repeatable workflows specific to this project** — a
deployment checklist, a release script, an issue-triage flow. They supplement
skills: skills are usually general; commands are project-specific orchestration.

## Conventions

- One `.md` file per command. Filename (without `.md`) becomes the command name.
- Frontmatter declares title, args, and allowed tools.
- Body is a deterministic playbook; embed shell via fenced code when a step
  should run literally.

## Example

```markdown
---
title: Release
description: Cut a release branch, bump version, tag, push
---

# Release

1. Ensure `main` is clean and up to date
2. Run `pnpm test`
3. Bump version in `package.json`
4. Commit as `chore: release vX.Y.Z`
5. Tag and push
```

Invoke: `/project:release`

## Skills vs. commands — when to use which

| Use a **skill** when | Use a **command** when |
|---|---|
| Reusable across projects | Specific to this repo |
| Encodes a decision playbook | Encodes a repeatable automation |
| Auto-triggered by task context | Invoked explicitly |

## Scope

This folder is **client-specific**. The Mindflayer toolkit ships its
cross-project automation as skills, not commands. Add commands as you find
workflows worth formalizing here.

## References

- Claude Code — Commands: https://docs.claude.com/en/docs/claude-code/commands
- Claude Code — Slash commands: https://docs.claude.com/en/docs/claude-code/slash-commands

# .claude/rules/

Modular, topic-focused guidance files that Claude Code loads contextually.

## Purpose

Rules extend `AGENTS.md` with fine-grained, file-specific or topic-specific
guidance. Claude automatically applies the relevant rule when it detects a
matching context (e.g., `testing.md` while writing tests, `code-style.md`
while editing code).

## Conventions

- One `.md` file per topic. Short, declarative, scannable.
- Use frontmatter to target files or paths when needed:
  ```yaml
  ---
  applies_to: "**/*.test.ts"
  ---
  ```
- Prefer imperative bullet points over prose.

## Typical files

- `code-style.md` — formatting, naming, structural preferences
- `testing.md` — test patterns, coverage expectations, fixtures
- `api-conventions.md` — error shapes, versioning, auth
- `security.md` — input validation, secrets handling

## Relationship to `AGENTS.md`

`AGENTS.md` is the cross-agent entry point and defines **what** this project is.
Rules define **how** to work inside it. Keep `AGENTS.md` stable and small; put
evolving, topic-specific guidance here.

## Scope

This folder is **client-specific**. The Mindflayer toolkit does not ship
rules. Add files as they become useful in the engagement; promote patterns
that generalize to the toolkit via a PR to Project-Mindflayer.

## References

- Claude Code — Skills and project layout: https://docs.claude.com/en/docs/claude-code/skills
- Claude Code — Memory: https://docs.claude.com/en/docs/claude-code/memory

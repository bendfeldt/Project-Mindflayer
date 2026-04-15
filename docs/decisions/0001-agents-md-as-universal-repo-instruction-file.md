# ADR-0001: AGENTS.md as Universal Cross-Platform Repo Instruction File

**Status:** Accepted
**Date:** 2026-03-01
**Deciders:** Michael Bendfeldt

## Context

AI coding assistants each have their own repo-level instruction file convention:
Claude Code reads `CLAUDE.md`, Codex reads `AGENTS.md`, Gemini CLI reads `GEMINI.md`.
In a multi-agent consultant workflow, all agents are active in the same repo simultaneously.

The question was whether to maintain a separate instruction file per agent or converge
on a single file that all agents read.

## Decision

We will use `AGENTS.md` as the universal repo-level instruction file across all supported
agents. Claude Code is configured to treat `AGENTS.md` as equivalent to `CLAUDE.md` by
including a pointer in the repo's `CLAUDE.md` file (`@AGENTS.md`).

## Alternatives Considered

### Alternative A: Separate file per agent
- **Pros:** Each agent gets a file in its native format with no compromises; full use of agent-specific features
- **Cons:** Requires maintaining 3–5 files with identical safety rules and platform context; drift between files is likely; new team members must learn which file to update

### Alternative B: CLAUDE.md as the primary, symlink or copy for others
- **Pros:** Keeps Claude Code's native format as the authority
- **Cons:** Symlinks are fragile across OS and git; copies drift; Codex does not follow symlinks in all environments

### Alternative C: AGENTS.md as primary (chosen)
- **Pros:** Codex-native format that Claude, Gemini, and Cursor also support; one file to maintain; safety rules are expressed once and read by all agents
- **Cons:** Loses some Claude-specific CLAUDE.md features (e.g. `@-includes`); repo-level CLAUDE.md becomes a thin pointer file

## Consequences

### Positive
- Single source of truth for platform context, safety rules, and build commands
- New client repo setup creates exactly one instruction file regardless of which agents are active
- `setup-repo` skill and installer only need to manage one template family

### Negative
- Claude-specific features like `@-include` directives cannot be used in `AGENTS.md`
- The repo's `CLAUDE.md` must exist as a pointer file, adding a small amount of indirection

### Risks
- If Codex changes its file convention, `AGENTS.md` loses its "native" status — but the cross-platform benefit remains

## References

- Codex documentation: `AGENTS.md` specification
- `/templates/AGENTS-*.md` — the three platform templates this decision governs

# ADR-0004: Skills Source Directory at Repo Root, Not .claude/skills/

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

Claude Code installs and reads skills from `~/.claude/skills/` (global) or
`.claude/skills/` (project-level). A natural question when structuring this distribution
repo is whether the source skills should live at `.claude/skills/` to mirror the
install destination.

## Decision

We will keep skills at the repo root under `skills/` rather than under `.claude/skills/`.

## Alternatives Considered

### Alternative A: `.claude/skills/` (mirror install destination)
- **Pros:** The repo itself becomes a working Claude Code project — you can use the skills directly without installing; directory structure mirrors the consumer's `~/.claude/` layout
- **Cons:** Creates a misleading implication that `.claude/` is the relevant scope — but Codex and other agents do not look in `.claude/`; signals Claude-only even though the toolkit is multi-agent; every path in `install.sh` and `test-install.sh` would reference `.claude/skills/` as a *source*, which is confusing when the installer also writes *to* `.claude/settings.json` at destinations

### Alternative B: `skills/` at repo root (chosen)
- **Pros:** Clearly signals "distribution staging area" rather than "agent-specific config"; keeps the distinction between *source* (`skills/`) and *destination* (`~/.claude/skills/`) explicit; installer paths are unambiguous
- **Cons:** Requires understanding that the install destination differs from the source location; skills cannot be used directly from a checkout without running the installer

## Consequences

### Positive
- The separation between source (this repo) and destination (consumer's `~/.claude/`) is clear
- Non-Claude agents reading this repo are not confused by a `.claude/`-centric layout
- Installer code is easier to reason about: `skills/adr/SKILL.md` → `~/.claude/skills/adr/SKILL.md`

### Negative
- A developer cloning this repo cannot invoke `/adr` in Claude Code without running the installer first
- Slight asymmetry between what lives in `skills/` here and what the consumer sees in `.claude/skills/`

## References

- `/install.sh` — `SKILL_FILES` array shows the `skills/` → `~/.claude/skills/` mapping
- ADR-0002 — context on the SKILL.md open standard and multi-agent portability requirement

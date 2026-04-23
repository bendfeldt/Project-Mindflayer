# ADR-0004: Skills Source Directory at Repo Root, Not .claude/skills/

**Status:** Accepted
**Date:** 2026-04-09
**Scope clarified:** 2026-04-23 (see ADR-0014)
**Deciders:** Michael Bendfeldt

## Context

Claude Code installs and reads skills from `~/.claude/skills/` (global) or
`.claude/skills/` (project-level). A natural question when structuring this distribution
repo is whether the source skills should live at `.claude/skills/` to mirror the
install destination.

> **Scope note:** This ADR is about *this distribution repo's own layout* —
> where the **source of truth** for skills lives inside Project-Mindflayer.
> It is **not** about how client repos are structured. Client repos created
> by `install.sh --project --tools claude` receive a per-project `.claude/`
> layout (see **ADR-0014**) where skills are copied as real files into
> `./.claude/skills/` so they travel with the git clone (including into
> Claude Cowork cloud VMs).

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
- Installer code is easier to reason about: `skills/adr/SKILL.md` → `~/.ai-toolkit/skills/adr/SKILL.md` (+ `~/.claude/skills/` when Claude selected)

### Negative
- A developer cloning this repo cannot invoke `/adr` in Claude Code without running the installer first
- Slight asymmetry between what lives in `skills/` here and what the consumer sees in `.claude/skills/`

## References

- `/install.sh` — `SKILL_FILES` array shows the `skills/` → `~/.ai-toolkit/skills/` mapping
- ADR-0002 — context on the SKILL.md open standard and multi-agent portability requirement
- ADR-0014 — per-project `.claude/` layout for **client** repos (complements this ADR)

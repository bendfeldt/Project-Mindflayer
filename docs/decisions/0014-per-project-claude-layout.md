# ADR-0014: Per-Project `.claude/` Layout for Client Repos

**Status:** Accepted
**Date:** 2026-04-23
**Deciders:** Michael Bendfeldt

## Context

Anthropic's Claude Code ships three surfaces that share the same engine
(terminal CLI, desktop "Code" tab, and desktop "Cowork" tab / `claude.ai/code`),
but they differ sharply in what they can see:

| Surface | Sees `~/.claude/skills/`? | Sees `./.claude/skills/`? |
|---|---|---|
| Terminal CLI / Desktop Code | Yes (local process on your machine) | Yes |
| Cowork / Web | **No** (runs in an Anthropic-managed cloud VM) | Yes (part of the git clone) |

Our toolkit, per ADR-0002, installs skills to `~/.ai-toolkit/skills/` with
symlinks from `~/.claude/skills/`. That made skills available to local Claude
CLI but invisible to Cowork, where the cloud VM has no access to the user's
home directory. Users correctly reported "skills aren't showing up in Cowork"
even though the toolkit was installed.

Two additional concerns surfaced during the design discussion:

- **Transparency** — teams want skills visible in the repo (PR-reviewable, greppable), not hidden under `~/`.
- **Bidirectional sync** — a skill authored or modified in a client repo must have a path back to the toolkit, mirroring the existing `/promote-adr` pattern.

## Decision

Adopt the community-canonical per-project `.claude/` layout for **client repos**:

```
client-repo/
├── AGENTS.md                 # cross-agent entry point (unchanged)
└── .claude/
    ├── settings.json         # profile permissions (unchanged)
    ├── skills/               # NEW: toolkit skills copied as real files
    ├── rules/                # NEW: scaffold for client-specific rules
    ├── commands/             # NEW: scaffold for repeatable workflows
    ├── agents/               # NEW: scaffold for sub-agents
    └── hooks/                # NEW: scaffold for event-driven scripts
```

`install.sh --project --tools claude` now:

1. Copies every toolkit skill (real files, not symlinks) from the manifest
   into `./.claude/skills/<name>/`.
2. Creates `rules/`, `commands/`, `agents/`, and `hooks/` with pointer
   `README.md` files explaining each folder's purpose.
3. Leaves `~/.claude/skills/` symlinks untouched for local CLI consumers.

The toolkit source of truth remains `~/.ai-toolkit/skills/`. Per-project
copies are **derived artifacts** refreshed via `install.sh --project` or
`tools/sync-skills.sh`.

## Alternatives Considered

### A. Hook-only bootstrap (no committed skills)

Add a `SessionStart` hook to `.claude/settings.json` that runs
`install.sh --global` inside the Cowork VM, guarded by `CLAUDE_CODE_REMOTE=true`.

- **Pros:** No drift (always fetches latest); no committed copies; minimal diff to current setup.
- **Cons:** Skills invisible in the repo (transparency failure); no artifact to promote from (`/promote-skill` impossible); runtime network dependency.
- **Rejected** because it fails both user requirements (transparency + promotion).

### B. Hybrid (chosen)

Commit skills to `./.claude/skills/` + keep `~/.ai-toolkit/skills/` as source
of truth + add drift tooling + add `/promote-skill`.

### C. Full realignment (project-first)

Strip `~/` of everything except identity/baseline; make every capability
per-project only.

- **Pros:** Maximum alignment with community-canonical structure.
- **Cons:** Large reorg; loses the cross-project "one install, all repos benefit" property that makes the toolkit valuable.
- **Rejected** as over-reach for the problem.

## Consequences

### Positive

- **Cowork works** — committed skills travel with the git clone into cloud VMs.
- **Transparent** — skills visible in PRs, greppable, inspectable without running any tool.
- **Per-project customization** — teams can tweak a skill for one client without affecting others.
- **Bidirectional sync** — `/promote-skill` closes the loop from client-repo edits back to the toolkit (symmetric with `/promote-adr`).
- **Matches community convention** — repos feel "standard Claude Code" to outsiders.
- **Non-Claude agents unaffected** — Codex, Gemini, Cursor, Copilot CLI continue to read `AGENTS.md` at the repo root and use `~/.ai-toolkit/skills/` via the global install.

### Negative

- **Drift risk** — N client repos carry N copies. Mitigated by:
  - Version headers on every `SKILL.md` (YAML frontmatter `version:` field).
  - `tools/check-skills-update.sh` detects stale skills.
  - `tools/sync-skills.sh` refreshes in place (with `--dry-run` and `--force`).
  - Re-running `install.sh --project` invokes the same drift-aware UX already used for templates.
- **Larger PRs on first project install** — ~10 skill files + 4 scaffold READMEs land in the initial diff. One-time cost.
- **Claude-centric folder name** — `.claude/` is a Claude convention. Codex/Gemini/Cursor/Copilot still rely on `AGENTS.md` at repo root; they do not read `.claude/`. This is accepted given Claude is the daily driver.

## Scope

This ADR governs the **layout of client repos managed by Mindflayer's
`--project` install.** It does **not** change:

- The layout of this distribution repo itself (see ADR-0004).
- The `--global` install path (still writes to `~/.ai-toolkit/` and symlinks
  `~/.claude/skills/`).
- The `SKILL.md` open standard or cross-agent `AGENTS.md` convention
  (ADR-0001, ADR-0002).

## References

- ADR-0001 — `AGENTS.md` as universal repo instruction file
- ADR-0002 — `SKILL.md` open standard for cross-agent skills
- ADR-0004 — Skills source directory at repo root (scope clarified by this ADR)
- Anthropic — Claude Code on the Web (cloud VM scope): https://docs.claude.com/en/docs/claude-code/claude-code-on-the-web
- Anthropic — Claude Code Skills: https://docs.claude.com/en/docs/claude-code/skills
- `install.sh` — `SKILL_FILES`, `SCAFFOLD_FILES`, and project-install claude branch
- `skills/promote-skill/SKILL.md` — bidirectional sync workflow
- `tools/check-skills-update.sh`, `tools/sync-skills.sh` — drift tooling

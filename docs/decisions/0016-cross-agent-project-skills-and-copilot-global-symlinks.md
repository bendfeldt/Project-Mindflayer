# ADR-0016: Cross-Agent Project Skills via `.claude/skills/` and Copilot CLI Global Symlinks

**Status:** Accepted
**Date:** 2026-04-28
**Deciders:** Michael Bendfeldt
**Amends:** [ADR-0014](0014-per-project-claude-layout.md)

## Context

[ADR-0014](0014-per-project-claude-layout.md) established that toolkit
skills are committed as real files into `<client-repo>/.claude/skills/`
so that Claude Cowork (cloud VM sessions) can see them. Its consequences
section claimed:

> Non-Claude agents unaffected — Codex, Gemini, Cursor, Copilot CLI
> continue to read `AGENTS.md` at the repo root and use
> `~/.ai-toolkit/skills/` via the global install.

That claim turned out to be wrong for **Copilot CLI** specifically.
Copilot CLI does not read from `~/.ai-toolkit/skills/` at all. Per the
official documentation
([docs.github.com/copilot/how-tos/copilot-cli/customize-copilot/add-skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)),
Copilot CLI loads skills from:

- **Personal (global):** `~/.copilot/skills/` or `~/.agents/skills/`
- **Project (repo):** `.github/skills/`, `.claude/skills/`, or
  `.agents/skills/`

Two consequences of this gap:

1. The toolkit's `--global` install symlinks skills only into
   `~/.claude/skills/`. Copilot CLI never sees them — even with a global
   install, toolkit skills are invisible.
2. The `--project` install copies skills into `.claude/skills/`, but the
   copy was nested **inside the `claude)` case branch** of
   `install.sh`. A user running `--project --tools copilot` (without
   `claude`) ended up with no skills directory at all. Copilot CLI
   therefore couldn't see them per-project either.

A real engagement surfaced this: a user installed the toolkit with
`--tools copilot` in a client repo, and the toolkit skills (`adr`,
`smart-commit`, `terraform-scaffold`, …) were unavailable from Copilot
CLI inside that repo.

## Decision

Two changes to the distribution model, both consistent with ADR-0014's
core thesis (skills travel with the repo / are visible to local agents):

### 1. Per-project skills are agent-neutral

The `Skills (project)` block in `install.sh` is lifted out of the
`claude)` case and runs whenever **either** `claude` or `copilot` is
selected (or both). The destination remains `.claude/skills/` because
Copilot CLI's docs explicitly accept that path as a project-skill
location — there is no need to duplicate into `.github/skills/`.

The Claude-specific scaffold folders (`rules/commands/agents/hooks`
READMEs) and `.claude/settings.json` continue to be Claude-only and
remain inside the `claude)` case.

### 2. Global Copilot install gets `~/.copilot/skills/` symlinks

When `--global --tools copilot` is selected, the installer creates
`~/.copilot/skills/<name>` symlinks pointing into
`~/.ai-toolkit/skills/<name>`, mirroring the existing logic for
`~/.claude/skills/`. Skills edited in the toolkit source propagate to
both Claude Code and Copilot CLI without further action.

### Implications for client-repo layout (no change)

```
<client-repo>/.claude/
├── settings.json          # Claude only — present iff --tools claude
├── skills/<name>/SKILL.md # Cross-agent — present iff --tools claude OR copilot
├── rules/README.md        # Claude only
├── commands/README.md     # Claude only
├── agents/README.md       # Claude only
└── hooks/README.md        # Claude only
```

### Updated truth table for skill visibility

| Surface                         | Sees `~/.ai-toolkit/skills/`? | Sees `~/.claude/skills/`? | Sees `~/.copilot/skills/`? | Sees `<repo>/.claude/skills/`? |
|---------------------------------|:------------------------------:|:--------------------------:|:---------------------------:|:-------------------------------:|
| Claude Code (local)             | via `~/.claude/skills/` symlinks | ✅ | — | ✅ |
| Claude Cowork (cloud VM)        | ❌ | ❌ | — | ✅ |
| Copilot CLI                     | ❌ | ❌ | ✅ (after this ADR) | ✅ |
| Codex / Gemini / Cursor         | indirectly via `AGENTS.md` references; no direct skill discovery | — | — | indirectly via `AGENTS.md` |

## Alternatives Considered

### Alternative A: Duplicate skills into `.github/skills/` for Copilot

Copilot CLI accepts `.github/skills/` as a project-skill location. We
could write skills there in addition to `.claude/skills/`.

- **Rejected.** Doubles the on-disk footprint of every committed skill,
  increases drift risk (N client repos × 2 trees), complicates the
  promote-skill flow. Copilot's own docs accept `.claude/skills/`
  unchanged, so duplication earns nothing.

### Alternative B: Keep skills only in `~/.copilot/skills/` (no per-repo copy for Copilot)

For Copilot users, rely solely on the global symlinks and skip the
per-project copy.

- **Rejected.** Breaks the ADR-0014 promise that skills travel with the
  git clone. A consultant who pulls a client repo on a fresh machine —
  or a Copilot Coding Agent cloud session that pulls the repo —
  wouldn't see toolkit skills until they ran the global installer.

### Alternative C: Move `.claude/skills/` to `.agents/skills/`

Both Claude Code and Copilot CLI accept `.agents/skills/`. Renaming the
folder would be more agent-neutral on its face.

- **Deferred.** Touches every client repo already using `.claude/skills/`
  and conflicts with ADR-0014's "matches community convention"
  rationale. Revisit if Anthropic or GitHub deprecate `.claude/skills/`
  as a recognized location, or if a third agent forces a different
  shared name.

## Consequences

### Positive

- Toolkit skills become visible to Copilot CLI both globally and
  per-project — closes the bug found in real use.
- Single source of truth for project skills (`<repo>/.claude/skills/`)
  is preserved; no duplication into `.github/skills/`.
- `~/.copilot/skills/` is wired up the same way as `~/.claude/skills/`,
  so promote-skill and sync-skills flows need no changes.
- The change is additive — existing Claude-only installs are unaffected.

### Negative

- `~/.copilot/skills/` users with a pre-existing skills directory could
  in principle collide with toolkit skill names. Mitigated by
  `safe_symlink`'s overwrite policy already used for
  `~/.claude/skills/`.
- One more directory under `$HOME` to keep tidy. The uninstaller already
  handles `~/.claude/skills/`; symmetric handling for
  `~/.copilot/skills/` is a small follow-up if not already covered.

### Amends ADR-0014

ADR-0014 §Consequences §Positive bullet "Non-Claude agents unaffected"
should be read as: **Codex, Gemini, and Cursor** are unaffected.
**Copilot CLI** sees the per-project skills via `.claude/skills/` and
the global skills via `~/.copilot/skills/` (this ADR).

## References

- ADR-0001 — `AGENTS.md` as universal repo instruction file
- ADR-0002 — `SKILL.md` open standard
- ADR-0014 — Per-project Claude layout (amended by this ADR)
- GitHub docs — Adding agent skills for GitHub Copilot CLI:
  https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills
- `install.sh` — `SKILL_FILES`, `TOOLKIT_SKILL_NAMES`, the per-project
  skill block (now agent-neutral), and the global Copilot symlink loop.
- `tests/test-install.sh` — regression test for `--project --tools
  copilot` populating `.claude/skills/`.

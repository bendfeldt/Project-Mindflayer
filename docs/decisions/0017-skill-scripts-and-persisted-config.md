# ADR-0017: Skills with Executable Scripts and Persisted Per-Engagement Config

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Michael Bendfeldt

## Context

Every toolkit skill up to now has been prose plus, at most, a `references/`
directory. `release-notes` is the first that ships **executable scripts** and the
first that needs to **remember settings between runs**.

It needs to remember things because it operates across a real engagement's
topology. One engagement observed at the time of writing has one Azure DevOps
org, **two** projects, and **14** repositories. A release touches a handful of
those repos, and the mapping from task titles to deployable item folders is a
team convention that cannot be derived from anything in the repo.

Two properties of that state pull in opposite directions:

| State | Nature | Wants to be |
|---|---|---|
| Engagement root, repo roster, local paths | Machine-specific — meaningless on a colleague's laptop | Local, uncommitted |
| Task title prefixes, item suffixes, language, merge-commit patterns | Team convention — everyone must agree | Committed, reviewable |

A single config file cannot satisfy both. Committing local paths pollutes the
client repo with one developer's directory layout; keeping conventions local
means every teammate re-answers the same questions and can silently disagree
about the mapping.

There is also a placement hazard. ADR-0014 established that client repos receive
real copies of toolkit skills under `.claude/skills/`, refreshed by
`install.sh --project` and `tools/sync-skills.sh`. Anything a skill writes inside
its own directory is **destroyed on the next refresh**.

## Decision

**1. Skills may ship executable scripts under `scripts/`.**

Scripts do deterministic, verifiable work — parsing diffs, calling APIs,
assembling structure. They must not generate prose; judgement stays with the
agent. Constraints:

- Python 3 standard library only. No dependency installation on a client machine.
- Invoked explicitly (`python3 scripts/x.py`), so no executable bit to preserve
  through `install.sh`'s copy path.
- Fragile pure logic ships with dependency-free assertions runnable via
  `python3 scripts/test_*.py`.
- All script output in English, per the baseline. Generated *content* follows the
  run's chosen language.

**2. Persisted config splits by what is machine-specific.**

```
~/.ai-toolkit/<skill>/engagements/<name>.json   # local: paths, roster, topology
<client-repo>/.claude/<skill>.config.json       # committed: team conventions
```

**3. Skill config never lives under `.claude/skills/`.** It sits at
`.claude/<skill>.config.json`, a sibling of the skills tree, because
`tools/sync-skills.sh` overwrites `.claude/skills/` wholesale.

**4. Bootstrap derives before it asks.** Anything recoverable from the git remote
— provider, org, project, repo — is detected and *confirmed*, never prompted
blind. Only genuine conventions are asked, in one round.

**5. `~/.ai-toolkit/<skill>/` is the home for skill-owned state**, alongside the
existing `skills/`, `docs/` and `templates/`. Run artifacts, caches and
engagement files go there — never in the client repo.

## Alternatives Considered

### A. One committed config per repo

Everything in `.claude/<skill>.config.json`, including paths.

- **Pros:** One file, shared with the team, nothing hidden.
- **Cons:** Local absolute paths in a client repo are noise at best and wrong for
  every other developer. A multi-repo run would have to re-locate sibling repos
  on each invocation.
- **Rejected** — commits machine state to a shared repo.

### B. All machine-local

Everything in `~/.ai-toolkit/`, nothing committed.

- **Pros:** Simplest; no client-repo footprint at all.
- **Cons:** Conventions stop being shared. Each teammate re-answers the prompts
  and can disagree about the task-title mapping, which silently produces
  different task-to-folder mappings for the same release.
- **Rejected** — conventions are precisely the thing that must not drift.

### C. Split (chosen)

Local roster plus committed conventions.

### D. No scripts; agent does everything inline

- **Pros:** No new precedent; skills stay pure prose.
- **Cons:** Diff parsing and TMDL evidence extraction are deterministic work an
  LLM does slowly, expensively and non-reproducibly. A wrong mapping writes wrong
  test instructions onto a real person's task.
- **Rejected** — determinism is the point.

## Consequences

### Positive

- **Conventions are reviewable.** The task-title mapping arrives in a PR and the
  team can argue about it before it mislabels a release.
- **Portable across engagements.** No client name, org or path is baked into a
  skill; a new engagement is one bootstrap away.
- **Testable.** `test_remote.py` caught that the previous single-format remote
  parser handled neither percent-encoded project names nor the Azure DevOps SSH
  `v3` form — both present in a live engagement.
- **Survives skill refresh.** Config outside `.claude/skills/` is untouched by
  `sync-skills.sh`.
- **Cheaper and reproducible.** Deterministic extraction runs the same way twice.

### Negative

- **Two files to reason about.** Mitigated by `config.py --show`, which prints one
  merged view, and `--validate`, which names what is missing.
- **Python becomes a soft dependency** for skills that use scripts. Acceptable —
  it is present on macOS and every engagement machine so far, and prose-only
  skills are unaffected.
- **Config schema drift.** Each config carries `version`; readers must tolerate
  older files rather than crash.
- **Larger skill payloads** in client repos — `release-notes` adds nine files
  rather than one. One-time cost per repo.

## Scope

Governs skills that ship scripts or persist configuration. It does **not** change:

- The `SKILL.md` open standard or its frontmatter (ADR-0002).
- The per-project `.claude/` layout or the skills-refresh model (ADR-0014).
- Prose-only skills, which remain the default and need none of this.

## References

- ADR-0002 — `SKILL.md` open standard for cross-agent skills
- ADR-0004 — Skills source directory at repo root
- ADR-0014 — Per-project `.claude/` layout for client repos
- ADR-0016 — Cross-agent project skills and Copilot global symlinks
- `skills/release-notes/` — first implementation of this pattern
- `tools/sync-skills.sh` — the refresh behaviour that forces config placement

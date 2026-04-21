# ADR-0013: Revert Personal Overlay and Client-ADR Templates

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt
**Supersedes:** [ADR-0012](0012-universal-baseline-plus-personal-layer.md)

## Context

[ADR-0012](0012-universal-baseline-plus-personal-layer.md) introduced a split of
`global/AGENTS.md` into:

1. A universal, shippable baseline (`global/AGENTS.md`) — universal data-consultant
   standards, Hard Rules, stack, compliance awareness
2. A per-consultant personal overlay (`~/.ai-toolkit/AGENTS.personal.md`, seeded from
   `global/AGENTS.personal.example.md`) — name, employer, role, country, additional
   languages, personal working notes

Each agent's global config was written as `concat(baseline, personal)` at install time.
Country-specific compliance content was moved into `templates/client-adrs/` (initially
containing `danish-public-sector-compliance.md`).

Shortly after landing, two problems surfaced:

**1. The personal overlay doesn't earn its complexity.**

The overlay's primary content is identity: name, employer, role, country, additional
languages. None of this operationally changes agent behavior:

- Language matching is already handled by the baseline instruction "respond in the
  language the consultant uses" — no declaration needed.
- Name, employer, role, and country are trivia; agents don't make different decisions
  based on them.
- Personal Hard Rules / session-carried lessons belong in session workspace (plan.md)
  or per-repo notes, not a global file.

The engineering cost to deliver this thin value was non-trivial:

- Extra distribution file (`AGENTS.personal.example.md`)
- Seed-on-first-run + byte-preserve-on-re-run logic in installer
- Concat-baseline-and-personal step in installer and `sync-global.sh`
- Personal-preservation carve-out in uninstaller
- ADR documenting the mechanism
- Anticipated future work: `/setup-personal` skill + detection hook

For content that doesn't meaningfully change how agents behave.

**2. Client-ADR templates belong in the client's repo, not this toolkit.**

`templates/client-adrs/danish-public-sector-compliance.md` was introduced as a home
for country-specific compliance content (Danish public sector laws: DS 484,
Databeskyttelsesloven, Forvaltningsloven, Offentlighedsloven, Arkivloven) moved out of
the personal overlay.

On reflection, client ADRs belong in the client's own repo (`docs/decisions/`), not
pre-canned in the toolkit:

- A consultant encountering a Danish public sector client writes the ADR *in that
  client's repo at that time*, tailored to that client's actual data flows.
- Pre-canned ADR templates invite copy-paste-without-thinking, which defeats the point
  of an ADR (to capture context and trade-offs for *this* decision, not to template
  someone else's).
- The existing `kimball` and `adr` skills already help draft fresh ADRs when needed.
- This toolkit's scope is baseline + skills + repo template — not client-specific
  content, and not regulatory reference material.

## Decision

Revert both mechanisms introduced for ADR-0012:

1. Remove the personal overlay entirely:
   - Delete `global/AGENTS.personal.example.md`
   - Remove seed/preserve/concat logic from `install.sh`
   - Revert `tools/sync-global.sh` to a simple copy of the baseline
   - Remove the personal-preservation carve-out from `tools/uninstall.sh`
   - Remove personal-overlay assertions from the test suite
   - Remove personal-overlay mentions from README, architecture docs, and copilot
     instructions

2. Remove the client-ADR template directory entirely:
   - Delete `templates/client-adrs/`
   - Remove `CLIENT_ADR_FILES` manifest and install logic from `install.sh`
   - Remove client-adr assertions from the test suite

3. Preserve the decision trail:
   - Mark ADR-0012 as Superseded with a supersession note pointing here
   - Write this ADR (0013) explaining the reversal

## What We Keep From the ADR-0012 Work

The baseline rewrite itself remains valuable and is kept:

- `global/AGENTS.md` as a universal, shareable data-consultant baseline
- Hard Rules in the baseline (not in a personal file)
- Cloud-first modern data stack content
- Universal GDPR / NIS2 / ISO 27001 awareness

The file is now the entirety of the global layer — there is no personal overlay on
top of it.

## Consequences

**Positive:**

- Simpler installer, simpler sync, simpler uninstaller
- Fewer moving parts to test and document
- Toolkit scope stays clean: baseline + skills + repo template. No personal identity
  management, no client-specific reference material.
- Baseline is now truly shareable across all consultants without per-person seed files

**Negative:**

- Consultants who already ran the previous installer have a seeded
  `~/.ai-toolkit/AGENTS.personal.md` that will no longer flow into their per-agent
  config. They can copy any content they want to keep into their per-agent config
  directly (`~/.claude/CLAUDE.md`, etc.) or into their session workspace.
- ADR-0012 landed on `origin/main` and is reverted in the next commit. This is
  deliberately documented rather than rebased away so the decision trail is honest.

**Neutral:**

- Consultants who want personal context can hand-edit their per-agent config directly,
  or fork the toolkit and customize `global/AGENTS.md`. This is an intentional
  "no batteries included for personal identity" stance.

## Final Layer Model

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: Baseline (global/AGENTS.md)                        │
│  Universal data-consultant standards, Hard Rules, stack,     │
│  compliance awareness. Shared across all consultants.        │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: Repo (./AGENTS.md)                                 │
│  Client-specific: name, platform, build commands, safety,    │
│  branching. Committed to each client repo.                   │
├──────────────────────────────────────────────────────────────┤
│  Layer 3: Skills (~/.ai-toolkit/skills/*/SKILL.md)           │
│  Reusable capabilities that adapt to the layers above.       │
└──────────────────────────────────────────────────────────────┘
```

Client-specific regulatory content (DS 484, GDPR implementation details, sector
rules, etc.) lives in the client repo's own `docs/decisions/`, written when that
decision is actually being made.

## References

- [ADR-0012](0012-universal-baseline-plus-personal-layer.md) — the superseded decision
- [ADR-0003](0003-thin-repo-templates-with-version-headers.md) — thin repo templates
- [ADR-0011](0011-tech-stack-conventions-as-adrs.md) — platform conventions as ADRs

# ADR-0012: Universal Baseline Plus Personal Layer for Global Instructions

**Status:** Superseded by [ADR-0013](0013-revert-personal-overlay-and-client-adrs.md)
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Supersession Note

The personal overlay mechanism introduced by this ADR was reverted one commit after
landing. The overlay primarily stored identity fields (name, employer, role, country,
additional languages) that do not operationally change agent behavior — the baseline
already instructs agents to respond in the consultant's language, and personal identity
doesn't meaningfully affect task execution. The engineering complexity (seed-on-first-run,
byte-preserve-on-re-run, concat-at-install-time) exceeded the value delivered.

See [ADR-0013](0013-revert-personal-overlay-and-client-adrs.md) for the reversal
rationale and the final three-layer model (Baseline / Repo / Skills).

The historical context below is retained for the decision trail.

---

## Context

Prior to this ADR, `global/AGENTS.md` was a single file that mixed two very different
kinds of content:

- **Universal data-consultant standards** — Hard Rules, engineering principles, Kimball
  and medallion architecture, modern data stack preferences, Conventional Commits,
  compliance awareness (GDPR, NIS2, ISO 27001).
- **One specific consultant's identity** — name, employer (twoday), role, country
  (Denmark), additional spoken language (Danish), and Danish public-sector law
  references (Databeskyttelsesloven, Forvaltningsloven, Offentlighedsloven, Arkivloven).

This coupling meant the toolkit could not be shared with another data consultant without
them editing the global file to strip out someone else's identity. The result was a
framework that looked and felt like a personal dotfile rather than a reusable toolkit.

ADR-0011 established the parallel pattern at the client layer: one universal `AGENTS.md`
template plus platform/client ADRs as first-class decisions. The consultant layer still
lagged behind — universal baseline and personal overlay were fused into one file.

The question was how to split global instructions so the baseline is shippable across
any data consultant while preserving a clean place for personal identity and preferences.

## Decision

We split the global layer into two files:

- **`global/AGENTS.md`** — universal data-consultant baseline. Shareable and shippable
  without modification. Contains the Hard Rules (planning, waiting for the user,
  secrets), engineering standards, Kimball/medallion guidance, modern data stack
  preferences, Conventional Commits format, and GDPR/NIS2/ISO 27001 awareness.
- **`global/AGENTS.personal.example.md`** — minimal personal overlay template. The
  consultant fills it in once: name, employer, role, country, additional spoken
  languages, and any personal notes.

The installer (`install.sh --global`) handles the two-file model as follows:

- Installs both files into `~/.ai-toolkit/`.
- On first run, seeds `~/.ai-toolkit/AGENTS.personal.md` from the `.example` file.
- On re-install, preserves `AGENTS.personal.md` byte-for-byte — the user owns it.
- Writes each agent's resolved config as `concat(baseline, personal)` at install time
  (e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/gemini/GEMINI.md`).
  Codex and Gemini do not support `@`-includes, so concatenation at install time
  ensures cross-agent parity without per-agent include mechanics.

Country-specific compliance references (previously embedded in the global file)
relocate to the client layer where they apply. A new template
`templates/client-adrs/danish-public-sector-compliance.md` captures the Danish
public-sector laws and ISMS context. Client repos adopt it by copying the ADR into
their own `docs/decisions/` folder.

## Alternatives Considered

### Alternative A: Keep global personal
- **Pros:** No installer changes; simpler distribution; one file to edit
- **Cons:** Blocks shareability — another consultant cannot use the toolkit without
  first scrubbing someone else's identity from the baseline; toolkit remains a
  personal dotfile rather than a reusable framework

### Alternative B: `@`-include only (no concat)
- **Pros:** Single source of truth per layer; no duplication at install time
- **Cons:** Codex and Gemini CLI do not support `@`-include syntax; cross-agent
  behavior would diverge; users would need to maintain parity manually

### Alternative C: Three sub-layers (universal / role / personal)
- **Pros:** Finer granularity; role-specific content (e.g. "data engineer" vs
  "analytics engineer") could live separately
- **Cons:** Over-engineered for current scope; no concrete demand for a role sub-layer;
  adds a file and a merge step with no corresponding benefit

### Alternative D: Larger personal layer (cloud preferences, primary language)
- **Pros:** Maximal personalization; zero assumptions in baseline
- **Cons:** Cloud-agnostic/cloud-first and English are universal defaults for modern
  data consultants; pushing these into personal would force every user to re-declare
  the obvious; baseline should carry sensible defaults, not be empty

### Alternative E: Hard Rules in personal
- **Pros:** Consultants could opt out of specific rules
- **Cons:** Hard Rules are guardrails (plan first, wait for the user, never expose
  secrets), not personality; any serious data consultant should operate under them
  by default; making them opt-in defeats their purpose

### Alternative F: Universal baseline + personal overlay (chosen)
- **Pros:** Baseline is shippable across any data consultant; personal file is
  user-owned and never overwritten; country-specific laws live with the clients they
  apply to; Hard Rules apply by default; parallels the template refactor from ADR-0011
  cleanly
- **Cons:** One extra file in the distribution; `sync-global.sh` must concatenate
  rather than copy; re-install logic must detect and preserve the personal file

## Consequences

### Positive
- Toolkit is shareable across any data consultant without editing baseline content
- Baseline rarely changes; personal file is user-maintained and stable across re-installs
- Country-specific laws live with the client they apply to, not the consultant identity
- Hard Rules apply to any serious consultant by default — no opt-in required
- Mirrors the ADR-0011 refactor at the consultant layer, giving the toolkit a
  consistent "universal + specific" structure across both global and repo scopes

### Negative
- One extra file to ship and document (`AGENTS.personal.example.md`)
- `sync-global.sh` must concatenate baseline + personal instead of a straight copy
- Re-install logic must detect an existing `AGENTS.personal.md` and preserve it
  byte-for-byte — accidental overwrite would clobber user identity

### Risks
- If a consultant never creates `AGENTS.personal.md`, resolved agent configs will
  contain only the baseline — acceptable, but worth surfacing in the installer output
- Baseline drift could re-introduce personal content if contributors are not careful
  — mitigated by keeping this ADR as the canonical reference for what belongs where
- Country-specific ADR templates could proliferate (Danish, Swedish, German, …) —
  acceptable; each is small and opt-in per client repo

## Supersession

- Partly supersedes the implicit prior convention that `global/AGENTS.md` is
  personal-per-consultant. It now ships as a universal baseline.
- Extends the layered configuration model established in ADR-0001 by making the
  global layer itself two-part (baseline + personal overlay).

## References

- Extends: `docs/decisions/0001-agents-md-as-universal-repo-instruction-file.md`
- Parallel refactor at client layer: `docs/decisions/0011-tech-stack-conventions-as-adrs.md`
- Referenced from baseline: `docs/decisions/platform/0011-safety-rules-for-all-agents.md`
- Changed files: `global/AGENTS.md`, `global/AGENTS.personal.example.md`,
  `install.sh`, `tools/sync-global.sh`, `templates/client-adrs/danish-public-sector-compliance.md`

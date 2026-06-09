# ADR-0015: ADR Location Hierarchy and Scope

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt

## Context

Decisions accumulate in three different layers in this consultancy practice:

1. Decisions about **the toolkit itself** (Project-Mindflayer) — how the
   installer works, how skills are distributed, how `AGENTS.md` is layered.
2. Decisions about **how we build on a given technology platform** —
   "this is how we do Terraform / Databricks / Fabric in general,
   regardless of client". Reusable across every engagement on that stack.
3. Decisions made **inside a specific client engagement** — the choices
   that engagement made, including any deviation from the platform default.

Until now these layers were not consistently separated. ADRs in
`docs/decisions/platform/` mixed two distinct things:

- Platform best practice that any engagement on that stack should follow.
- Engagement-specific narrative ("this repo deviates", "this engagement
  asked for…", references to a specific client codebase).

The result: a reader can't tell whether an ADR is prescribing a general
pattern or recording a one-off choice. ADR-0013 already established that
client-specific compliance ADRs belong in the client's own repo. This
ADR generalises that principle and codifies the full hierarchy.

## Decision

We adopt a **three-layer ADR hierarchy** with a strict rule about what
each layer may contain.

### Layer 1 — Toolkit ADRs

**Location:** `docs/decisions/` (this repository, root of the decisions
folder).

**Scope:** Decisions about Project-Mindflayer itself. The installer,
skill distribution, the `AGENTS.md` / `CLAUDE.md` layering model, the
SKILL.md format, this hierarchy itself.

**Audience:** Anyone working on the toolkit.

**Examples:** ADR-0001 (`AGENTS.md` as universal repo instruction file),
ADR-0014 (per-project `.claude/` layout), this ADR.

### Layer 2 — Platform ADRs

**Location:** `docs/decisions/platform/` (this repository).

**Scope:** Generic best practice for a technology platform. Stack-scoped
(Terraform, Databricks, Fabric, cross-cutting). Must be applicable to
**any** engagement on that platform.

**Hard constraints — a Platform ADR MUST NOT contain:**

- Client, company, or project names.
- Concrete repository names tied to a specific engagement.
- Repository-specific paths (e.g. `infrastructure/azure_lakehouse/...`)
  or module names that exist only in one client codebase.
- Phrasing such as "this repo", "this engagement", "this team", "the repo
  committed to…". Platform ADRs do not have a "this" — they describe a
  pattern, not a state.

**Hard constraints — a Platform ADR MUST contain:**

- A `Scope` field naming the platform(s) it applies to.
- A `General Principle` section: the universal intent, expressed as
  stack-agnostically as the topic allows.
- A `Technology-Specific Application` section: how the principle is
  realised in the concrete tech.

**Audience:** Any consultant starting a new engagement on that stack.

**Examples (post-rewrite):** ADRs 0019–0038 covering Terraform module
structure, OIDC, Unity Catalog, medallion layout, secret scope, etc.

### Layer 3 — Client-Repo ADRs

**Location:** Inside the client repository, at `docs/decisions/` or
`docs/adr/`.

**Scope:** Decisions specific to that engagement. May reference
the engagement's repo, modules, naming, and concrete files freely —
that is the point of this layer.

**A Client-Repo ADR is the correct home for:**

- Deviations from a Platform ADR. The ADR must reference the platform
  ADR being deviated from in an `Engagement-Specific Deviation` section
  and explain why.
- Choices that are inherently engagement-specific (the client's project
  prefix, the client's CI/CD connection name, the client's compliance
  context, the client's chosen optional modules).
- Anything tied to a single concrete codebase.

**Audience:** Engineers working on that engagement.

### Templates

We ship two ADR templates in `docs/decisions/templates/`:

- `adr-platform-template.md` — for Layer 2 ADRs.
- `adr-client-template.md` — for Layer 3 ADRs. Includes the
  `Engagement-Specific Deviation` section.

Both templates follow the same skeleton: Status / Scope / Context /
General Principle / Technology-Specific Application / Alternatives /
Consequences. The client template adds the deviation section.

### Promotion and supersession

If an engagement-level decision turns out to apply broadly, promote it:
copy the content to a new Platform ADR, strip all client/codebase-specific
wording per the Layer 2 constraints, and link from the original
Client-Repo ADR. The reverse — pulling a Platform ADR into a client repo
to deviate — is done by writing a new Client-Repo ADR that references the
platform ADR and explains the deviation.

When two Platform ADRs conflict, the older one is marked **Superseded**
with a `Superseded-by:` header and a banner pointing to the replacements.
Conflicts are not resolved by silent edits.

## Alternatives Considered

### Alternative A: Two layers only (toolkit + client)

Fold platform best practice into either the toolkit baseline or the
individual client repos.

- **Rejected.** Toolkit baseline must remain stack-agnostic to be
  shippable; per-client copies cause drift between engagements that all
  picked the same Terraform-on-Databricks pattern. The platform layer
  earns its place by being the deduplicated home for "how we do Terraform".

### Alternative B: One flat folder, distinguish by tag in frontmatter

Keep all ADRs in one folder, mark each `scope: toolkit | platform | client`.

- **Rejected.** Folders give visible boundaries; tags are easy to
  forget and easy to ignore when reading. The constraint "Platform ADRs
  contain no client names" is much easier to enforce when there's a
  visible folder boundary.

### Alternative C: Per-platform subfolders (`platform/terraform/`, `platform/databricks/`)

Split the platform layer further by stack.

- **Deferred.** Not needed at current ADR count. Revisit if
  `docs/decisions/platform/` exceeds ~50 ADRs or if cross-platform ADRs
  become awkward. ADR numbering is shared across platforms regardless of
  folder structure.

## Consequences

- ADRs 0021–0038 must be rewritten to satisfy Layer 2 constraints. They
  are currently engagement-coupled (references to a specific Terraform
  codebase, client name, repo paths) and read as engagement minutes
  rather than platform guidance. A separate work item handles the rewrite.
- ADR-0019 conflicts with the new Layer 2 ADRs (0022–0024) and will be
  marked Superseded.
- Any new ADR landing in `docs/decisions/platform/` is reviewed against
  the Layer 2 constraints before merge. A grep sweep for client/company
  names and repo-specific paths is part of the review.
- Engagements that need to deviate from a Platform ADR write a
  Client-Repo ADR using `adr-client-template.md` and reference the
  platform ADR being deviated from.
- The toolkit's own future decisions stay at `docs/decisions/` and use
  no special template — they are the same shape as ADRs 0001–0014.

## Related

- ADR-0001 — `AGENTS.md` as universal repo instruction file.
- ADR-0013 — Reverted personal overlay; established that client-specific
  ADRs belong in the client's repo.
- ADR-0014 — Per-project `.claude/` layout in client repos.

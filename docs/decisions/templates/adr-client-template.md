# ADR-NNNN: <Short Title>

**Status:** Proposed | Accepted | Superseded | Deprecated
**Date:** YYYY-MM-DD
**Deciders:** <names>
**Supersedes:** <ADR-XXXX> (optional)
**Superseded-by:** <ADR-XXXX> (optional)

**Scope:** <Engagement / repo name>

<!--
  This template is for **Client-Repo ADRs** that live inside a client
  engagement's repository (typically docs/decisions/ or docs/adr/).

  Client-Repo ADRs may freely reference the engagement's codebase,
  module names, naming conventions, compliance context, etc. — that is
  the purpose of this layer.

  See ADR-0015 (in the toolkit) for the full hierarchy: toolkit /
  platform / client.

  When this ADR records a deviation from a Platform ADR, fill in the
  "Engagement-Specific Deviation" section. Otherwise, omit it.
-->

## Context

Describe the engagement-specific problem space. Reference the actual
repo, modules, and constraints freely.

## General Principle

If this decision instantiates a Platform ADR, restate the principle in
one or two sentences and link the Platform ADR. If the decision is
purely engagement-specific (no platform analogue), say so.

## Engagement-Specific Application

How the principle is realised in this codebase. Concrete file paths,
module names, environment values, naming. This is where engagement
detail belongs.

## Engagement-Specific Deviation

*(Include this section only when deviating from a Platform ADR.)*

- **Platform ADR being deviated from:** <ADR-XXXX> — <title>
- **Nature of the deviation:** <one paragraph>
- **Why this engagement deviates:** <reason — client constraint, legacy
  system, regulatory requirement, performance need, etc.>
- **Scope of the deviation:** Does it apply to one module, one
  environment, the whole repo? Is it temporary?
- **Revisit trigger:** What would cause this engagement to fall back in
  line with the Platform ADR? (e.g. "when client approves OIDC
  federation", "when the legacy system is decommissioned")

If the deviation reveals a flaw in the Platform ADR rather than an
engagement-specific need, raise that separately and consider
superseding the Platform ADR.

## Alternatives Considered

### Alternative A: <name>
- **Pros:** …
- **Cons:** …
- **Rejected because:** …

## Consequences

- <consequence>
- <consequence>

## Related

- ADR-XXXX (Platform) — <how it relates>
- ADR-XXXX (this repo) — <how it relates>

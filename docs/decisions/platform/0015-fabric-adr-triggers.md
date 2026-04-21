# ADR-0015: Fabric Per-Client ADR Triggers

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

The platform ADRs (0012, 0013, 0014) establish default conventions for Fabric engagements,
but many architectural decisions are client-specific and cannot be standardized across
all projects. Without a clear list of decision points that require per-client ADRs,
teams either:

- Apply defaults blindly even when inappropriate for the client context
- Make ad-hoc decisions without documentation
- Revisit the same decisions repeatedly during the engagement

This ADR defines which architectural choices require a per-client ADR in the client's
repo, not in the toolkit.

## Decision

Create a per-client ADR in the client's `docs/decisions/` directory for:

1. **Lakehouse vs. Warehouse choices** — when to store data in Warehouse instead of Lakehouse (e.g., small reference tables, frequently-joined dimensions)

2. **Semantic model design** — composite models (DirectLake + Import for external sources), aggregation layers, calculated tables

3. **Dataflow Gen2 vs. Spark notebooks** — when to use low-code Dataflow Gen2 vs. Spark notebooks for transformations

4. **Workspace boundary decisions** — how many workspaces, which items belong in each, when to split a workspace by domain vs. environment

5. **Row-level security (RLS) strategy** — static roles, dynamic RLS via expressions, integration with Entra ID, performance implications

6. **DirectLake vs. Import mode** — when to fall back to Import mode for specific semantic models (e.g., external data sources, aggregation requirements)

7. **Capacity sizing and autoscale** — when to use autoscale, burst limits, SKU selection rationale

Each ADR should document:
- The specific client context that led to the decision
- Alternatives considered with trade-offs
- The chosen approach and implementation details
- Performance, cost, and compliance implications

## Alternatives Considered

### Alternative A: No per-client ADRs, apply defaults always
- **Pros:** Simplest approach, fastest onboarding, no documentation overhead
- **Cons:** Ignores client-specific constraints (compliance, budget, existing systems); leads to suboptimal designs; no record of why exceptions were made

### Alternative B: Per-client ADRs for all decisions (including defaults)
- **Pros:** Complete documentation of every choice, even when defaults are appropriate
- **Cons:** Documentation burden discourages use; ADR fatigue; most ADRs would say "we followed the default because no special considerations apply"

### Alternative C: ADR triggers list (chosen)
- **Pros:** Balances documentation with pragmatism; focuses on decisions where context matters; provides a checklist during project kickoff
- **Cons:** Requires judgment to determine when a decision crosses the ADR threshold; list may need updates as platform conventions evolve

### Alternative D: Decision log instead of ADRs
- **Pros:** Lower barrier to entry, faster to write, less formal structure
- **Cons:** Decision logs lack the rationale and alternatives documentation that ADRs provide; harder to search and reference later

## Consequences

### Positive
- Clear checklist for project kickoff and architecture review sessions
- Client-specific decisions are documented with rationale and trade-offs
- New team members can onboard by reading client ADRs alongside platform ADRs
- Reduces repeated conversations about why a specific approach was chosen

### Negative
- Requires discipline to create ADRs during fast-moving projects
- Teams must distinguish between "this is a deviation from the default" (ADR needed) vs. "this is a detail within the default" (no ADR needed)
- ADRs can become outdated if the architecture evolves and they are not updated

### Risks
- If ADR triggers list is too broad, teams may skip documentation to avoid overhead
- If too narrow, important decisions may go undocumented
- Clients unfamiliar with ADRs may resist the documentation practice

## References

- `templates/AGENTS-fabric.md` — superseded platform template containing the original ADR triggers list
- `templates/AGENTS.md` — universal template that references this ADR
- ADR-0012: Fabric Medallion Layer Architecture
- ADR-0013: Fabric Semantic Model Design Standards
- ADR-0014: Fabric Git Integration Policy

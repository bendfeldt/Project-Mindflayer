# ADR-0018: Databricks ADR Triggers

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Databricks projects involve design decisions that vary per client, source system, and
workload. The question was which decisions are standardized globally (via platform
ADRs like 0016 and 0017) versus which decisions require per-client documentation
(via repo-level ADRs).

Without clear triggers, teams either document everything (ADR fatigue, noise) or
document nothing (context loss, repeated debates, onboarding friction).

## Decision

Create a **per-client ADR** for the following decision types:

1. **Grain and SCD decisions** — table grain (one row per what?), Slowly Changing Dimension strategy (Type 0/1/2/3/6), effective dating patterns
2. **Compute choices** — Photon enablement beyond gold layer, cluster sizing justification, instance type selection (memory-optimized, compute-optimized, GPU)
3. **DLT vs. notebook decisions** — when to use Delta Live Tables vs. plain notebooks, streaming vs. batch processing
4. **Source system onboarding patterns** — how new sources are integrated (API, SFTP, CDC, direct query), connection management, schema evolution handling
5. **Data quality rules** — expectations enforcement (DLT expectations vs. manual checks), quarantine vs. reject strategies

These decisions are **client-specific** or **workload-specific** and cannot be
standardized globally. They require context: business requirements, data volume,
latency SLAs, compliance constraints, and source system characteristics.

Do **not** create ADRs for: standard Unity Catalog structure (covered by ADR-0016),
default compute tiers (covered by ADR-0017), or routine code changes.

## Alternatives Considered

### Alternative A: No per-client ADRs, rely on code comments and wiki
- **Pros:** Less ceremony; faster iteration; no ADR maintenance burden
- **Cons:** Context loss over time; decisions are invisible to new team members; debates recur; no change history; wiki drifts from code
- **Rejected:** ADRs are lightweight (markdown, version-controlled, adjacent to code) and solve a real problem (context retention)

### Alternative B: Mandate ADRs for every design decision
- **Pros:** Maximum documentation; every choice is explained
- **Cons:** ADR fatigue; noise overwhelms signal; teams skip ADRs or write low-quality ones; reviewing code becomes reviewing ADRs
- **Rejected:** Over-documentation is as harmful as under-documentation — focus on decisions with multi-month or multi-team impact

### Alternative C: ADRs only for architectural changes (pipelines, layers)
- **Pros:** Restricts ADRs to high-level system design; avoids low-level implementation details
- **Cons:** Misses critical decisions like SCD strategy or compute sizing that are not "architectural" but have significant long-term impact
- **Rejected:** The goal is to document decisions that future engineers will need to understand — implementation-level choices like SCD Type 2 vs. Type 1 fit that criteria

### Alternative D: Use GitHub issues or PRs for decision context
- **Pros:** Decisions are linked to the code changes that implement them; searchable via GitHub
- **Cons:** Issues are closed and buried; PRs focus on implementation not rationale; searching across closed issues is difficult; no standard format
- **Rejected:** ADRs provide a durable, discoverable, structured format — issues are ephemeral by nature

## Consequences

### Positive
- Clear boundary between platform defaults (ADRs 0016/0017) and client-specific decisions (repo-level ADRs)
- New team members can read ADRs to understand "why" without needing to trace git history or ask senior engineers
- Design debates are settled once and referenced later ("see ADR-0023 for why we chose Type 2 SCDs")
- ADRs are version-controlled and adjacent to the code they govern

### Negative
- Requires discipline to write ADRs during initial design rather than retroactively
- Teams may over-index on ADRs and slow down delivery if not balanced correctly
- "Should this be an ADR?" itself becomes a decision point (resolved by this document)

### Risks
- If the five trigger categories are too narrow, important decisions go undocumented — revisit this list as patterns emerge
- If teams write ADRs after implementation rather than during design, ADRs become justifications not decisions
- ADRs may fall out of sync with code if not updated when decisions change (tooling like `tools/check-adr-drift.sh` can help)

## References

- `templates/AGENTS.md` — universal repo instruction file referencing this ADR per platform
- Superseded `templates/AGENTS-databricks.md` — original source of this convention (line 50-51)
- ADR-0016: Unity Catalog structure (standardized, not a per-client trigger)
- ADR-0017: Compute defaults (standardized, but exceptions require ADRs per this rule)
- Kimball dimensional modeling: SCD types are a core decision point requiring documentation

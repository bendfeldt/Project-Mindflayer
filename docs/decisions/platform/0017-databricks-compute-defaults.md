# ADR-0017: Databricks Compute Defaults

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Databricks workloads require compute resources (clusters or SQL warehouses) with
varying performance, cost, and isolation characteristics. The question was how to
standardize compute configuration across environments and layers to balance cost
efficiency in development with performance and isolation in production.

Without defaults, teams over-provision dev clusters, under-provision prod workloads,
or fail to enable Photon for gold-layer SQL queries where it provides the largest
performance benefit.

## Decision

We adopt a **two-tier compute model**:

**Development:**
- Use **shared interactive clusters** (small, auto-terminating) or **SQL warehouses** (Serverless, size Small)
- Cost optimization over isolation — multiple users, ephemeral workloads, fast startup

**Production:**
- Use **dedicated job clusters** (ephemeral, created per job run)
- Enable **Photon** for gold-layer SQL workloads (dimensional model queries)
- No shared clusters — each production job gets isolated compute to prevent resource contention

Gold-layer queries benefit most from Photon acceleration due to their SQL-heavy nature
(star schema joins, aggregations). Bronze and silver layers typically use PySpark or
streaming, where Photon provides less benefit.

## Alternatives Considered

### Alternative A: All-purpose clusters for everything
- **Pros:** Simplest model; one cluster type; no job cluster startup latency
- **Cons:** Dev and prod share compute (bad isolation); long-running clusters cost more than ephemeral job clusters; no auto-termination in prod; difficult to size correctly
- **Rejected:** Violates environment isolation, increases cost, and complicates capacity planning

### Alternative B: Photon everywhere (all layers, all environments)
- **Pros:** Maximum performance; no decision fatigue; simpler configuration
- **Cons:** Photon premium pricing for workloads that don't benefit (PySpark, bronze ingestion); wasted cost in dev; over-provisioning
- **Rejected:** Photon is best suited for vectorized SQL execution — applying it to PySpark-heavy bronze/silver layers is wasteful

### Alternative C: Serverless SQL for production
- **Pros:** No cluster management; instant startup; auto-scaling; pay-per-query
- **Cons:** Not available for PySpark workloads; higher per-DBU cost; limited customization (no init scripts); region availability varies
- **Rejected:** Serverless SQL is ideal for ad-hoc analytics but not suitable for production data pipelines requiring PySpark, DLT, or custom libraries

### Alternative D: Dedicated clusters per job (always-on)
- **Pros:** No startup latency; consistent performance; easier debugging
- **Cons:** Clusters run 24/7 whether jobs are executing or not; dramatically higher cost; wastes resources overnight and weekends
- **Rejected:** Job clusters (ephemeral, per-run) provide the same isolation at a fraction of the cost

## Consequences

### Positive
- Clear cost/performance boundary: dev optimizes for cost, prod optimizes for isolation and reliability
- Photon usage is targeted where it provides the largest benefit (gold-layer SQL)
- Job clusters prevent resource contention between production workloads
- Auto-terminating shared clusters in dev reduce idle compute costs

### Negative
- Job cluster startup latency (1-3 minutes) delays production job execution compared to always-on clusters
- Teams must understand when to use Photon vs. standard runtime — requires training
- Shared dev clusters can still experience resource contention during peak usage

### Risks
- If production workloads require PySpark with high parallelism, Photon may still be beneficial — this default can be overridden per-pipeline via ADR
- Very frequent small jobs (e.g., every 5 minutes) may suffer from job cluster startup overhead — consider always-on clusters for high-frequency workloads
- Serverless SQL may become cost-effective for production as Databricks pricing evolves — revisit this decision annually

## References

- `templates/AGENTS.md` — universal repo instruction file referencing this ADR per platform
- Superseded `templates/AGENTS-databricks.md` — original source of this convention
- Databricks Photon engine: vectorized SQL execution optimized for data warehousing queries
- Job clusters documentation: ephemeral compute created per-run, terminated on completion

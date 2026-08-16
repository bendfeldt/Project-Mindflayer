# Data Engineering Audit

Trace each pipeline from source to consumer and inspect:

- Batch versus streaming fit, ingestion contracts, schema evolution, and input validation.
- Idempotency, restartability, checkpointing, retries, failure isolation, and dead-letter handling.
- Incremental processing, backfills, late-arriving data, duplicate handling, and reconciliation.
- Orchestration dependencies, concurrency, environment parity, configuration, ownership, and observability.
- Freshness, lineage, data-quality controls, storage formats, partitioning, clustering, and indexing where applicable.
- Compute and query efficiency, unnecessary data movement, and repeated transformations.

Look for reusable ingestion, validation, retry, transformation, and persistence components. Keep source-specific behavior explicit; do not force unrelated sources through a generic framework.

Flag overly fragmented pipelines when stages add orchestration, serialization, or operational failure points without creating a meaningful contract, ownership boundary, reuse point, or independent scaling need.

For reliability findings, identify the failure scenario, current recovery behavior, possible correctness impact, and the smallest safe remediation. Do not assume exactly-once behavior from framework names alone.

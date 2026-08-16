# Analytics Engineering Audit

Inspect source, staging, intermediate, mart, and semantic layers for:

- Declared model grain, business and surrogate keys, relationship cardinality, and join correctness.
- Conformed dimensions, slowly changing dimensions, late-arriving facts, null handling, and temporal logic.
- Duplicated business rules, repeated metrics, repeated `CASE` expressions, and inconsistent semantic definitions.
- Incremental predicates, materialization strategy, tests, documentation, lineage, naming, and ownership.
- Excessive CTE nesting, `SELECT *`, unused columns, expensive models, and transformations placed in the wrong layer.
- Business logic embedded in dashboards that should be governed upstream.

Where dbt is present, inspect project configuration, source declarations, model contracts, generic and singular tests, macros, snapshots, exposures, documentation, and incremental model correctness. Prefer existing macros only when their contract is clear; do not hide simple SQL behind unnecessary indirection.

For templated SQL, prefer `dbt parse`, `dbt compile`, or the configured dialect tooling. A generic SQL engine rejection is not proof when templates remain unresolved. Preserve and verify the exact expression before reporting a syntax or semantic defect; do not rebuild SQL from terminal summaries.

Tie every dimensional-model recommendation to a concrete grain, history, consistency, or query-use requirement. Do not prescribe Kimball patterns when the workload does not benefit from them.

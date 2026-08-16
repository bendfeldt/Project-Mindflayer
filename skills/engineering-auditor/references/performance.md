# Performance and Efficiency Audit

Inspect runtime, database, storage, network, orchestration, and cost behavior for:

- N+1 access, repeated database or API round trips, and sequential work that can safely run concurrently.
- Full scans, missing predicate or partition pruning, inefficient joins, unnecessary sorts, and early expensive operations.
- Repeated transformation, serialization, materialization, data copying, and redundant computation.
- Incorrect incremental processing, caching, partitioning, clustering, indexing, or storage formats.
- Excessive memory, CPU, distributed compute, data movement, orchestration overhead, or retained intermediates.

Classify each conclusion:

- Measured: supported by a benchmark, profile, query plan, trace, or production metric.
- Highly probable: the execution mechanism and cost are evident, but measurement is unavailable.
- Speculative: plausible and worth measuring, not a proven problem.

Explain the performance mechanism and expected benefit. Prefer recommendations such as applying a partition predicate before a join over vague advice such as “optimize the query.” Include correctness, operability, and cost trade-offs; faster is not automatically better.

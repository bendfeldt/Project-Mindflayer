# Software Engineering Audit

Inspect architecture and implementation for:

- Cohesive module boundaries, dependency direction, separation of concerns, and explicit interfaces.
- Functions or classes with unrelated responsibilities, complex branching, hidden side effects, or difficult test seams.
- Duplicated code, validation, configuration, retries, logging, error handling, and API access.
- Specific exceptions, actionable errors, consistent logging, and observable failure behavior.
- Unit and integration coverage around critical contracts and failure paths.
- Dead code, unused dependencies, unnecessary wrappers, inconsistent naming, and accidental complexity.
- CI/CD validation, reproducible builds, dependency pinning, and environment parity.

Respect sound repository conventions. Recommend a different architectural pattern only when it materially improves correctness, isolation, testability, reuse, or change cost.

Treat large files and functions as investigation signals rather than defects. Identify the mixed responsibilities or change coupling before recommending decomposition.

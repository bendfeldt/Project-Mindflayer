# Audit Framework

## Scope and discovery

Define the boundary before inspecting details. For a local PR or code change, review the diff and enough surrounding repository context to understand contracts and conventions. State exclusions and evidence limitations in the report.

Discover before judging:

- Languages, frameworks, databases, data platforms, cloud providers, and orchestrators.
- Build, dependency, test, lint, format, security, and CI/CD tooling.
- Entrypoints, module boundaries, data flows, deployment units, and ownership boundaries.
- Repository instructions, documented architecture, and accepted decisions.

Prefer configured tooling. Do not add a second linter, scanner, formatter, retry library, or orchestration pattern when the repository already has a suitable one.

## Analysis sequence

1. Run deterministic, non-mutating checks appropriate to the repository.
2. Trace critical flows from input through validation, transformation, persistence, and output.
3. Identify root causes rather than symptoms.
4. Consolidate overlapping observations into one finding with multiple domains.
5. Rank findings by priority, severity, confidence, impact, and effort.
6. Recommend the minimum sufficient change.

## Modularity and reuse

Actively compare similar modules, SQL models, pipelines, configuration, validation, retries, logging, error handling, and API integration. Recommend a shared building block only when the behavior should evolve together and reuse improves consistency, reliability, testability, or change cost.

Treat these as warning signals, not automatic findings:

- Similar code with different domain rules.
- A wrapper used once.
- Small explicit duplication clearer than a generic abstraction.
- Layering that hides rather than simplifies data flow.

Prefer fewer concepts, dependencies, wrappers, stages, and hidden side effects. Delete unnecessary code before refactoring it.

## Evidence and deduplication

Use one finding per root cause. Attach every applicable domain. A repeated SQL rule that causes inconsistency and repeated compute belongs in one Analytics Engineering, Software Engineering, and Performance finding.

Use exact paths and line numbers. When evidence is repository-wide, list representative locations and explain how the search established scope. Do not expose secret values in evidence.

## Scorecard

Score only applicable domains with whole numbers from 1 to 10. Use `Not assessed` when evidence is insufficient or a domain is irrelevant. Support each score with cited findings or verified strengths; do not calculate a false-precision weighted average.

# Project Instructions

<!-- template: AGENTS-databricks | version: 1.0.0 | updated: 2026-03-24 -->
<!-- To check for updates: diff this file against ~/.claude/docs/repo-templates/AGENTS-databricks.md -->

## Repo Identity

- **client:** {CLIENT_NAME}
- **platform:** databricks
- **repo_type:** data-platform
- **catalog_pattern:** `{client}_{environment}`

## Client Conventions

- **Language preference:** {PySpark | Spark SQL | both}
- **Notebook naming:** `{layer}_{entity}` (e.g., `bronze_orders`)
- **DLT pipeline naming:** `{client}-{env}-{layer}`

## Unity Catalog Structure

```
catalog: {client}_{env}
├── bronze    ← raw ingestion
├── silver    ← cleansed, deduplicated
├── gold      ← dimensional model
└── sandbox   ← ad-hoc (dev only)
```

## Compute

- **Dev:** shared cluster or SQL warehouse (small)
- **Prod:** dedicated job clusters, Photon enabled for gold-layer SQL

## Build & Run

```bash
databricks bundle validate
databricks bundle deploy -t {environment}
databricks bundle run {pipeline_name} -t {environment}
```

## dbt Integration

{If applicable:}
- Adapter: `dbt-databricks`
- Profiles target matches environment name
- Models target `gold` schema, sources from `bronze`/`silver`

## Branching

- `main` — production, protected
- `feature/{description}` — short-lived, one approval required
- CI: `databricks bundle validate` on PR

## ADR Triggers

Create an ADR for: grain and SCD decisions, compute choices (Photon, cluster sizing),
DLT vs. notebook decisions, source system onboarding patterns.

## Client-Specific Compliance

{Edit per client — PII masking rules, data retention, access control model, etc.}

## Safety Rules — All Agents

These rules apply regardless of which coding agent is used on this repo.

- **NEVER** read, display, log, or expose `.env` files, secrets, credentials, tokens, or private keys
- **NEVER** read files matching: `*.env*`, `*secret*`, `*credential*`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*token*`, `.netrc`, `.pgpass`, `*.tfvars`
- **NEVER** output values of environment variables containing SECRET, TOKEN, KEY, PASSWORD, or CREDENTIAL
- **NEVER** run deploy, apply, destroy, or other state-changing commands without explicit human confirmation
- **NEVER** run destructive file operations (`rm -rf`, etc.) without explicit human confirmation
- **NEVER** push to remote repositories without explicit human confirmation
- When referencing secrets in code, always use vault lookups or environment variable references — never literal values
- If you need to verify a secret exists, check for the file or variable name only — never output its value

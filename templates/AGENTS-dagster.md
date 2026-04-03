# Project Instructions

<!-- template: AGENTS-dagster | version: 1.0.0 | updated: 2026-03-24 -->
<!-- To check for updates: diff this file against ~/.claude/docs/repo-templates/AGENTS-dagster.md -->

## Repo Identity

- **client:** {CLIENT_NAME}
- **platform:** dagster
- **repo_type:** orchestration
- **deployment:** {k3s-helm | docker-compose}
- **python_version:** 3.11+

## Client Conventions

- **Asset naming:** `{layer}_{source}_{entity}` (e.g., `bronze_erp_orders`)
- **Job naming:** `{layer}__{source}_job`
- **Target platform:** {databricks | fabric | trino} (what Dagster orchestrates)

## Project Structure

```
dagster_project/
├── dagster_project/
│   ├── definitions.py
│   ├── assets/{bronze,silver,gold}/
│   ├── resources/
│   ├── jobs/
│   ├── schedules/
│   ├── sensors/
│   └── partitions/
├── tests/
├── pyproject.toml
├── dagster.yaml
└── workspace.yaml
```

## Key Design Choices

- Assets over ops — Software-Defined Assets for lineage and selective materialization
- One asset = one table/view in target platform
- IO Managers handle storage — assets don't know about platform details
- Resources for external connections, injected via Definitions

## dbt Integration

{If applicable:}
- `dagster-dbt` for lineage-aware orchestration
- dbt runs inside Dagster — not scheduled separately

## Environment Config

- **Dev:** Docker Compose, local PostgreSQL, filesystem IO manager
- **Prod:** K3s + Helm, managed PostgreSQL, object storage IO manager
- Config via environment variables, never hardcoded

## Build & Run

```bash
dagster dev                                # Local development
dagster job execute -j {job_name}          # Run specific job
pytest tests/ -v                           # Tests
ruff check dagster_project/                # Linting
```

## Deployment

- Image: built from Dockerfile, pushed to `{container_registry}`
- Helm chart: Dagster official, deployed via Terraform
- CI: `ruff check` + `pytest` + `dagster definitions validate` on PR
- CD: build image → push → Helm upgrade

## Branching

- `main` — production
- `dev` — development
- `feature/{description}` — short-lived, one approval required

## ADR Triggers

Create an ADR for: asset vs. op design, partition strategy, sensor vs. schedule,
IO Manager selection, run launcher/executor choices.

## Client-Specific Compliance

{Edit per client — log retention, secret management, PII in logs policy, etc.}

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

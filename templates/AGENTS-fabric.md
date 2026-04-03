# Project Instructions

<!-- template: AGENTS-fabric | version: 1.0.0 | updated: 2026-03-24 -->
<!-- To check for updates: diff this file against ~/.claude/docs/repo-templates/AGENTS-fabric.md -->

## Repo Identity

- **client:** {CLIENT_NAME}
- **platform:** microsoft-fabric
- **repo_type:** data-platform
- **workspace_pattern:** `{ClientPrefix}-{Env}-{Verb}`

## Client Conventions

- **Workspace prefix:** `{ClientPrefix}` (e.g., `PN`, `KBT`)
- **Lakehouse naming:** `{ClientPrefix}{Env}{Verb}` (e.g., `PNProdPersist`)
- **Warehouse naming:** `{ClientPrefix}{Env}Serve`
- **Capacity SKU:** {F4 | F8 | F16 | ...}
- **Capacity region:** {North Europe | West Europe}

## Architecture

```
Ingest    ← Pipelines, Dataflows, Shortcuts
Transform ← Spark notebooks
Persist   ← Lakehouse (Delta tables)
Serve     ← Warehouse (SQL views), Semantic models
Report    ← Power BI reports
```

- Data lands in Lakehouse, is served from Warehouse
- Semantic models source from Warehouse views, not lakehouse tables directly

## Semantic Models

- Format: TMDL in git
- One model per business domain
- Reports connect via live connection (DirectLake preferred over Import)
- Naming: `SM_{Domain}` for models, `RPT_{Domain}_{Name}` for reports

## Git Integration

- Fabric Git integration enabled per workspace
- `main` → prod workspaces, `dev` → dev workspaces
- **In git:** notebooks, TMDL, pipeline JSON
- **Not in git:** data, lakehouse metadata, capacity config (Terraform-managed)

## Branching

- `main` — production workspaces, protected
- `dev` — development workspaces
- `feature/{description}` — merged to `dev` then `main`

## ADR Triggers

Create an ADR for: Lakehouse vs. Warehouse choices, semantic model design (composite,
DirectLake vs. Import), Dataflow Gen2 vs. Spark, workspace boundary decisions, RLS strategy.

## Client-Specific Compliance

{Edit per client — data residency, PII masking, column-level security, etc.}

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

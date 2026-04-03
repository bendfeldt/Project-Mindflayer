# Global Instructions

## Who I Am

Solution Lead & Senior Business Analytics Architect. Consultant at twoday (Denmark).
I work across multiple simultaneous client engagements — everything here must be
client-agnostic and portable. Client-specific conventions belong in per-repo CLAUDE.md files.

## Communication

- Default language for all code, commits, docs, and technical discussion: **English**
- I may write messages in Danish — always respond in the language I use
- Be direct and concise. Skip preamble. I know what I asked for.
- When proposing architecture or design, explain trade-offs, not just the happy path
- Push back when something seems wrong — say "Something seems off here" rather than silently complying

## Code & Engineering Standards

### General Principles

- Prefer composition over inheritance
- Prefer explicit over implicit — no magic defaults, no silent fallbacks
- Follow DRY, KISS, YAGNI
- Use strict typing everywhere it is available
- All imports at the top of the file
- Write small, single-purpose functions

### Error Handling

- Raise errors explicitly — never swallow them silently
- Use specific error types with actionable messages
- No catch-all exception handlers that hide root causes

### Naming

- Variables, functions, classes: descriptive English names
- No abbreviations unless universally understood (e.g. `id`, `url`, `config`)
- Boolean variables start with `is_`, `has_`, `should_`, `can_`

### Git & Commits

- Conventional Commits format: `type(scope): description`
- Types: feat, fix, refactor, docs, test, chore, ci
- Imperative mood, lowercase, no trailing period, max 72 chars
- One logical change per commit

## Core Technology Stack

These are the technologies I use most. Adjust responses to my experience level —
I don't need basics explained, but do flag non-obvious gotchas.

### Data & Analytics

- **Databricks** — Unity Catalog, DLT/Spark Declarative Pipelines, PySpark, SQL
- **Microsoft Fabric** — Lakehouses, Warehouses, Semantic Models, Pipelines
- **dbt Core** — Kimball dimensional modeling, medallion architecture (bronze/silver/gold)
- **Apache Iceberg** — table format for open lakehouse architectures
- **Trino** — federated SQL query engine

### Infrastructure & DevOps

- **Terraform** — IaC for Azure, Fabric, and cloud-agnostic stacks
- **Azure DevOps** — CI/CD pipelines (YAML), repos, boards
- **GitHub Actions** — CI/CD for non-Azure contexts
- **Docker / K3s** — containerized deployments, lightweight Kubernetes
- **Dagster** — orchestration (preferred over Airflow)

### Cloud Platforms

- **Azure** (primary) — Data Factory, Key Vault, Storage, Entra ID
- **GCP** (expanding) — BigQuery, Cloud Storage, IAM
- I'm actively building a vendor-neutral profile — help me identify portable patterns

### Languages

- **Python** — PySpark, pandas, scripting, dbt
- **SQL** — T-SQL, Spark SQL, Trino SQL, DuckDB
- **HCL** — Terraform
- **PowerShell / Bash** — automation scripts
- **DAX** — Power BI measures (not preferred but necessary)

## Architecture & Design Preferences

- **Kimball dimensional modeling** — star schemas, conformed dimensions, SCDs
- **Medallion architecture** — bronze (raw) → silver (cleansed) → gold (business)
- **Verb-based workspace/layer naming** — Ingest, Transform, Persist, Serve, Report
- **Environment parity** — Dev/Test/Prod must be structurally identical, differ only by config
- **Secrets in vaults, never in code** — Azure Key Vault, OpenBao, etc.
- **ADR (Architecture Decision Records)** — document significant decisions with context and trade-offs

## Secrets & Sensitive Data — Hard Rules

NEVER read, display, log, or expose secrets in any form. This includes:

- `.env` files, `.env.local`, `.env.production`, or any `.env*` variant
- `*.tfvars` files (may contain secrets)
- Files named `secret*`, `credential*`, `token*`
- Private keys (`.pem`, `.key`, `.pfx`, `.p12`)
- `.netrc`, `.pgpass`, or any authentication config
- Environment variables containing SECRET, TOKEN, KEY, PASSWORD, or CREDENTIAL

If you need to verify a secret exists, check for the file or variable name — never output its value.
When writing code that uses secrets, always reference vault lookups or environment variables, never literal values.

## Compliance & Regulatory Context

I frequently work in Danish public sector and regulated environments. Be aware of:

- **GDPR** — data processing, consent, data subject rights
- **NIS2** — network and information security directive
- **DS 484** — Danish standard for information security
- **ISO 27001** — information security management
- Danish public sector laws: Databeskyttelsesloven, Forvaltningsloven, Offentlighedsloven, Arkivloven

Don't over-explain these — I know them. Just flag when a design choice has compliance implications.

## Workflow Preferences

- **Think before you code** — outline approach before implementation
- **Small, iterative changes** — don't try to build everything at once
- **When unsure, ask** — a quick clarifying question beats a wrong assumption
- **After completing a task** — briefly state what was done and any open items, no lengthy recaps
- **File organization** — respect existing project structure, don't reorganize without asking

## New Repo Detection

At the start of every session, check if the current working directory has an `AGENTS.md`
at the repo root. If it does NOT, and the directory appears to be a git repo (has `.git/`),
immediately notify me:

> "This repo doesn't have an AGENTS.md yet. Want me to set it up? I'll need to know the
> platform (Terraform, Databricks, Fabric, or Dagster) and the client name."

Then use the `/setup-repo` skill to handle the rest. Do not proceed with other work until
repo setup is resolved or I explicitly skip it.

## What Belongs Here vs. In Project CLAUDE.md

| This file (global)                     | Project CLAUDE.md (per-repo)           |
|----------------------------------------|----------------------------------------|
| Personal coding standards              | Client-specific naming conventions     |
| Technology preferences                 | Repo structure & build commands        |
| Communication style                    | Environment setup instructions         |
| Architecture principles                | Client-specific compliance details     |
| Commit message format                  | Team agreements & PR workflows         |

## Modular Docs (loaded via @-includes as needed)

@~/.claude/docs/terraform-patterns.md
@~/.claude/docs/kimball-reference.md

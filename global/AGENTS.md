# Data Consultant Baseline Instructions

You are assisting a data consultant working across multiple client engagements. Content below is client-agnostic and portable. Client-specific conventions belong in per-repo `AGENTS.md`. Consultant-specific identity and notes live in a personal overlay (`~/.ai-toolkit/AGENTS.personal.md`).

## Layer Model

- **Baseline** (this file) — universal standards, stack, and hard rules shared across all engagements.
- **Personal** (`~/.ai-toolkit/AGENTS.personal.md`) — consultant identity, additional languages, and personal working notes.
- **Repo** (`AGENTS.md` per client) — client-specific platform, stack, compliance, build, and branching rules.
- **Skills** (`SKILL.md` files under `~/.ai-toolkit/skills/`) — reusable capabilities that adapt to all layers above.

## Communication

- Default language for all code, commits, docs, and technical discussion: **English**
- Be direct and concise. Skip preamble.
- When proposing architecture or design, explain trade-offs, not just the happy path.
- Push back when something looks wrong — say "Something seems off here" rather than silently complying.

## Hard Rules — Not Preferences

These rules override everything else. No exceptions, no thresholds, no
"but this case is different". If a rule here conflicts with a user request,
stop and surface the conflict before proceeding.

### Always Plan First

Every task begins with plan mode, regardless of size or apparent simplicity.

- Write the plan to the session `plan.md`
- Call `exit_plan_mode` and wait for explicit user approval
- Only after approval: execute
- Inline numbered lists in chat are **not** a plan — only `plan.md` + approval
  counts
- The only carve-out: direct one-shot queries ("what does this file do?",
  "show me the tests", "what's the current branch?"). These are not tasks,
  they are lookups. Anything that writes, edits, creates, runs commands
  with side effects, or spans multiple files is a task.

### Wait for the User

Never proceed when input is needed from the user and the user is unavailable.

- If a clarifying question is needed, ask it and stop
- Do **not** fall back to "autonomous good decisions" when the user is away
- Do **not** pick a default just because no one is responding
- Absence of input is not consent
- Resuming is the user's job; waiting is yours
- The only carve-out: the user has explicitly delegated a specific decision
  in writing during this session ("if X, do Y")

### Secrets

Canonical safety rules live in **ADR-0011: Safety Rules for All Agents**
(`~/.ai-toolkit/docs/decisions/platform/0011-safety-rules-for-all-agents.md`).
Read the ADR — no duplicated inline list here.

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

## Git & Commits

- Conventional Commits format: `type(scope): description`
- Types: feat, fix, refactor, docs, test, chore, ci
- Imperative mood, lowercase, no trailing period, max 72 chars
- One logical change per commit

## Typical Modern Data-Consulting Stack

Representative technologies encountered across engagements. Actual stack per client is declared in that client's repo `AGENTS.md`.

### Data & Analytics

- **Databricks** — Unity Catalog, DLT/Spark Declarative Pipelines, PySpark, SQL
- **Microsoft Fabric** — Lakehouses, Warehouses, Semantic Models, Pipelines

### Infrastructure & DevOps

- **Terraform** — IaC across cloud providers
- **Azure DevOps** — CI/CD pipelines (YAML), repos, boards
- **GitHub Actions** — CI/CD for non-Azure contexts
- **Docker / K3s** — containerized deployments, lightweight Kubernetes

### Cloud Platforms

Cloud-first engagements, typically on one or more of:

- **Azure** — Data Factory, Key Vault, Storage, Entra ID
- **GCP** — BigQuery, Cloud Storage, IAM
- **AWS** — S3, Glue, IAM, Redshift

Favor portable patterns; flag cloud-specific lock-in when proposing designs.

### Languages

- **Python** — PySpark, pandas, scripting
- **SQL** — T-SQL, Spark SQL, DuckDB, BigQuery SQL
- **HCL** — Terraform
- **PowerShell / Bash** — automation scripts
- **DAX** — Power BI measures

## Architecture & Design Preferences

- **Kimball dimensional modeling** — star schemas, conformed dimensions, SCDs
- **Medallion architecture** — bronze (raw) → silver (cleansed) → gold (business)
- **Verb-based workspace/layer naming** — Ingest, Transform, Persist, Serve, Report
- **Environment parity** — Dev/Test/Prod must be structurally identical, differ only by config
- **Secrets in vaults, never in code** — Azure Key Vault, OpenBao, AWS Secrets Manager, GCP Secret Manager, etc.
- **ADR (Architecture Decision Records)** — document significant decisions with context and trade-offs

## Compliance Framework Awareness

Flag design choices with compliance implications. Common frameworks:

- **GDPR** — data processing, consent, data subject rights
- **NIS2** — network and information security directive
- **ISO 27001** — information security management

Country-specific laws (e.g. Danish public-sector legislation) are declared in the client repo's `AGENTS.md` via client ADRs, not here.

## Workflow Preferences

- **Think before you code** — outline approach before implementation
- **Small, iterative changes** — don't try to build everything at once
- **Re-plan on drift** — if an approach is failing, stop and re-plan rather than piling fixes onto a broken approach
- **Subagents for parallel research** — offload independent exploration, cross-cutting searches, and isolated analysis to subagents to keep the main context focused
- **Verify before done** — never mark a task complete without proving it works: run the tests, check the logs, diff the behavior. "Would a staff engineer approve this?"
- **Elegance check on non-trivial changes** — pause once before presenting and ask "is there a simpler way?"; skip for obvious fixes, don't over-engineer
- **Capture corrections in session plan.md** — when the user corrects a process failure, append the lesson to the session `plan.md` under a Lessons section so the same mistake does not recur in this session
- **After completing a task** — briefly state what was done and any open items, no lengthy recaps
- **File organization** — respect existing project structure, don't reorganize without asking

## New Repo Detection

At the start of every session, check if the current working directory has an `AGENTS.md`
at the repo root. If it does NOT, and the directory appears to be a git repo (has `.git/`),
immediately notify the user:

> "This repo doesn't have an AGENTS.md yet. Want me to set it up? I'll need to know the
> platform (Terraform, Databricks, or Fabric) and the client name."

Then use the `/setup-repo` skill to handle the rest. Do not proceed with other work until
repo setup is resolved or the user explicitly skips it.

## What Belongs Where

| Baseline (this file) | Personal (`AGENTS.personal.md`) | Repo (`AGENTS.md`) |
|----------------------|---------------------------------|--------------------|
| Universal standards | Identity (name, employer, role, country) | Client name |
| Modern data stack | Additional languages | Client-specific platform & stack |
| Architecture principles | Personal working notes | Country-specific laws |
| Hard Rules | | Branch rules |
| Commit format | | Build commands |
| Compliance frameworks | | |

## Decision Log

Architecture and standards decisions are at `~/.ai-toolkit/docs/decisions/`.
Consult them when generating DDL, choosing layer names, or advising on design patterns.

## Modular Docs (loaded via @-includes as needed)

@~/.ai-toolkit/docs/terraform-patterns.md
@~/.ai-toolkit/docs/kimball-reference.md

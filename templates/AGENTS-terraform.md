# Project Instructions

<!-- template: AGENTS-terraform | version: 1.0.0 | updated: 2026-03-24 -->
<!-- To check for updates: diff this file against ~/.claude/docs/repo-templates/AGENTS-terraform.md -->

## Repo Identity

- **client:** {CLIENT_NAME}
- **platform:** terraform
- **repo_type:** infrastructure
- **cloud_provider:** azure | gcp | multi-cloud
- **environments:** dev, test, prod

## Client Conventions

- **Resource prefix:** `{prefix}`
- **Region:** `westeurope`
- **Resource group naming:** `{prefix}-{env}-rg-{purpose}`
- **Subscription:** {subscription_name_or_id}

## Remote State

- **Storage account:** `{state_storage_account_name}`
- **Container:** `tfstate`
- **Key pattern:** `{environment}.tfstate`

## Authentication

- **CI/CD:** Service Principal via Azure DevOps service connection `{connection_name}`
- **Local dev:** `az login`

## Build & Run

```bash
cd environments/{env}
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform fmt -check -recursive
```

## Pipeline

- **Location:** `pipelines/` or `.azuredevops/`
- **CI (PR):** validate + plan on dev
- **CD (merge):** plan → approve → apply (dev → test → prod)

## Branching

- `main` — protected, production-ready
- `feature/{description}` — short-lived, one approval required

## ADR Triggers

Create an ADR for: new modules, provider/service selection, state backend changes,
authentication approach changes, anything with cross-environment blast radius.

## Client-Specific Compliance

{Edit per client — data residency requirements, network isolation rules, etc.}

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

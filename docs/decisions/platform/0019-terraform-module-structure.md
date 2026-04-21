# ADR-0019: Terraform Module Structure and Operating Model

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Terraform infrastructure repositories need consistent organization for remote state,
authentication patterns, environment isolation, and CI/CD integration. Without
standard conventions, each client engagement invents its own structure, leading to
fragmented onboarding, inconsistent security posture, and duplicated effort when
team members move between projects.

The question was how to structure Terraform projects so that state management,
authentication, and deployment pipelines follow a predictable pattern across Azure,
GCP, and multi-cloud engagements.

## Decision

We adopt a per-environment directory structure with remote state backends, service
principal authentication for CI/CD, and `az login` for local development. All
patterns are documented in `docs/terraform-patterns.md` (remote state examples,
for-each patterns, Key Vault secrets). The `AGENTS.md` template captures client-specific
values: state storage location, subscription, resource prefix, and CI/CD connection
names.

### Directory Structure
```
environments/
  dev/
    main.tf
    variables.tf
    backend.tf
  test/
  prod/
modules/
  {module_name}/
pipelines/
  terraform-ci.yml
  terraform-cd.yml
```

### Remote State
- Azure Storage backend with container `tfstate`, key pattern `{environment}.tfstate`
- GCS backend with bucket `terraform-state-{project}`, prefix `{environment}`
- State storage account and key patterns specified per repo in `AGENTS.md`

### Authentication
- **CI/CD:** Service Principal via Azure DevOps service connection (name in `AGENTS.md`)
- **Local dev:** `az login` (Azure) or `gcloud auth application-default login` (GCP)

### Pipeline Workflow
- **CI (PR):** `terraform validate` + `terraform plan` on dev environment
- **CD (merge to main):** plan → human approval → apply, sequenced dev → test → prod

## Alternatives Considered

### Alternative A: Terraform Workspaces
- **Pros:** Single directory, no code duplication, workspace-based isolation
- **Cons:** Shared backend file increases blast radius; workspace confusion common; harder to diff environments; state file conflicts under concurrent runs

### Alternative B: Per-environment folders (chosen)
- **Pros:** Explicit environment isolation; easier CI/CD parallelization; clear diffs; independent state files
- **Cons:** Requires copying `main.tf` structure (mitigated by using modules); slightly more boilerplate

### Alternative C: Monolithic root-level tfvars files
- **Pros:** Single `main.tf` at root
- **Cons:** No physical isolation between environments; easy to accidentally apply dev config to prod; state file shared across all environments

### Authentication Alternative: OIDC Workload Identity
- **Pros:** No long-lived secrets; ephemeral tokens; better security posture
- **Cons:** Requires Entra ID app registration; more complex setup; not all clients have approved OIDC federation

### Authentication Alternative: Managed Identity (Azure Pipelines)
- **Pros:** No credentials in pipeline config
- **Cons:** Only works for Azure-hosted agents; does not support GCP or multi-cloud

## Consequences

### Positive
- Consistent structure across all Terraform repos — new team members onboard faster
- Physical environment isolation reduces blast radius of misconfigurations
- Remote state backends prevent concurrent modification conflicts
- Service Principal authentication provides auditability and scoped permissions
- `docs/terraform-patterns.md` serves as quick-reference for common patterns

### Negative
- Per-environment folders duplicate some boilerplate (mitigated by using shared modules)
- Service Principals are long-lived credentials (rotation required)
- State backend must be provisioned before first `terraform init` (chicken-and-egg)

### Risks
- If state storage account is accidentally deleted, all state is lost (requires immutable backup policy and soft delete)
- Service Principal credential leakage grants full subscription access (requires secrets policy, Key Vault storage, and `.tfvars` in `.gitignore`)

## References

- `docs/terraform-patterns.md` — remote state examples, Fabric provider patterns, Key Vault secrets
- `templates/AGENTS.md` — universal repo instruction file (replaces per-platform templates)
- `templates/AGENTS-terraform.md` — superseded platform-specific template (content extracted to this ADR)

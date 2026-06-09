# ADR-0021: Use AzureRM Remote State Backend for Multi-Environment Terraform

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure

## Context

A multi-environment Azure Databricks Lakehouse (typically `dev`, `test`, `prd`)
is operated by multiple principals: humans on local CLIs, GitHub Actions
runners, and Azure DevOps agents. Terraform state is the shared source of
truth for what has been provisioned; if state is local to one machine,
collaboration breaks, state locking is impossible, and environment
promotion becomes error-prone.

The question is where and how to persist Terraform state so that:

- Multiple agents can plan and apply safely with locking.
- State is encrypted at rest, versioned, and co-located with the workloads.
- Backend credentials are never embedded in the repository.

## General Principle

Terraform state belongs in a **remote, locked, access-controlled backend
that lives in the same trust boundary as the workloads it manages**.
Backend parameters should be injectable at `init` time so that one root
module can serve many environments, each with its own state object.

## Technology-Specific Application

Use the `azurerm` Terraform backend with backend parameters supplied at
`terraform init -backend-config=...` rather than hard-coded:

```hcl
# backend.tf
terraform {
  backend "azurerm" {
    # use_azuread_auth = true
  }
}
```

Backend parameters (`storage_account_name`, `container_name`,
`resource_group_name`, `key`) are passed by the deploy pipeline using values
declared per environment (e.g., a small per-env config file consumed by the
pipeline). One state storage account is provisioned per environment so that
plans against different environments cannot collide on a lock.

### Recommended shape

- One storage account per environment, named with an environment suffix.
- Container: `tfstate`. Key: `terraform.tfstate`.
- Account is `StorageV2`, `Standard_LRS` (state is small and re-creatable
  metadata, GZRS is overkill), with blob soft delete and container soft
  delete enabled, public blob access disabled, TLS 1.2 minimum.
- The state storage account lives in the same Azure region as the workloads
  so metadata stays inside the same data-residency boundary.
- The pipeline self-heals the bootstrap — if the state account is missing it
  is created before `terraform init`. Place a delete lock on the resource
  group holding state accounts.

### Trade-offs in this realisation

- Self-healing bootstrap logic lives in CI YAML, which is harder to lint and
  test than HCL.
- State files can contain values from `sensitive` outputs; backend ACLs and
  region pinning are load-bearing.

## Alternatives Considered

### Alternative A: Local state on the developer machine
- **Pros:** Zero infrastructure to bootstrap; simplest developer ergonomics.
- **Cons:** No locking; unsafe with multiple operators; state lost if a
  laptop dies; no audit trail.
- **Rejected because:** Incompatible with CI/CD and team collaboration.

### Alternative B: Terraform Cloud / HCP Terraform
- **Pros:** Managed locking, run history, RBAC, policy-as-code.
- **Cons:** External SaaS dependency; data-residency questions for state
  containing Azure resource metadata; extra licensing.
- **Rejected because:** Introduces a vendor outside the Azure trust
  boundary that holds metadata about the workloads it manages.

### Alternative C: Azure Storage with hard-coded backend parameters in HCL
- **Pros:** Single `terraform init` with no `-backend-config` flags.
- **Cons:** Couples the code to one environment's storage account; forces
  per-env branches or per-env `backend.tf` files.
- **Rejected because:** Breaks the "one root, many environments" model.

## Consequences

- Pipelines plan and apply concurrently against different environments
  without lock contention; each environment has its own state account.
- State is encrypted at rest and protected by Azure RBAC plus soft delete.
- Accidental deletion of a state storage account loses environment state
  unless soft delete and a resource-group delete lock are in place.
- The bootstrap-on-demand step adds a small amount of CI YAML that is
  harder to test than HCL; treat it as infrastructure code regardless.

## Related

- ADR-0022 — OIDC federated identity used by the same pipelines to
  authenticate to Azure.
- ADR-0023 — Single-root Terraform layout that this backend pattern
  supports across environments.

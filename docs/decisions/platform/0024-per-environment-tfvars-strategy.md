# ADR-0024: Per-Environment `.tfvars` with `locals.tf` for Cross-Env Constants

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure

## Context

A single Terraform root (ADR-0023) is reused across multiple environments
(typically `dev`, `test`, `prd`). Environments differ in:

- Resource group and subscription.
- Admin / service principal object IDs.
- VNet CIDR ranges and feature flags.
- Storage SKU, tier, and replication defaults.
- Tagging (cost centre, criticality, budget).

Other values are constant across every environment — project name,
location, region, organisation egress IP — and should not be repeated.

## General Principle

Environment configuration splits cleanly into **two layers**:

- **Cross-environment constants** belong in code (a `locals` block) so
  that a rename happens in exactly one place.
- **Per-environment values** belong in data (`<env>.tfvars`) so that
  environment promotion is a data change, not a code change.

Sensitive identifiers (subscription ID, tenant ID, client IDs of the
deploy principal) belong in **neither** — they come from the pipeline's
authenticated session and are injected as `TF_VAR_*` environment variables.

## Technology-Specific Application

```hcl
# locals.tf — constant across environments
locals {
  project_name = "<client>"
  location     = "West Europe"
  region       = "westeurope"
  company_ip   = "203.0.113.10"   # placeholder — corporate egress IP
}
```

```hcl
# environments/dev.tfvars — differs per environment
environment              = "dev"
resource_group_name      = "rg-<client>-dev"
aad_admin_object_id      = "00000000-0000-0000-0000-000000000000"
vnet_cidr_range          = "10.10.0.0/16"
public_subnet_cidr_range = "10.10.0.0/17"
private_subnet_cidr_range = "10.10.128.0/17"

enable_vnet                            = true
deploy_datafactory                     = true
deploy_sql_server                      = false
deploy_event_hub                       = false
deploy_lighthouse_documentation_site   = true

datalake_sku                     = "Standard"
datalake_account_replication_type = "LRS"

tags = {
  cost_center = "..."
  criticality = "low"
}
```

Pipelines select an environment with
`terraform plan -var-file=environments/<env>.tfvars`. OIDC-derived
identity (ADR-0022) supplies `TF_VAR_AZURE_*` so that subscription IDs
and tenant IDs are never committed.

### Defaulting strategy

Variables that are conceptually per-environment but have a strong
default (e.g. the medallion `container_list`, ADR-0029) carry that
default in `variables.tf`. An environment overrides only when it
deviates. This keeps tfvars files short and intent-focused.

### Trade-offs in this realisation

- Two-place lookup: an engineer reading the input set must check both
  `locals.tf` and the active `<env>.tfvars`.
- A constant such as a single `company_ip` becomes a fragility if the
  office moves or a new region is added — every plan then carries a
  network-rule churn.
- A typo in the wrong tfvars can grant or revoke admin in a single
  environment without touching the others; the small blast radius is
  the design intent, but the diff alone does not reveal scope.

## Alternatives Considered

### Alternative A: Single `.tfvars` with `terraform.workspace`-keyed maps
- **Pros:** One file; explicit lookups.
- **Cons:** Workspaces also separate state, doubling their meaning;
  large maps become unreadable; per-env override is awkward.
- **Rejected because:** Conflates two responsibilities (selection +
  data) and is not the recommended Terraform pattern for distinct envs.

### Alternative B: Everything in `locals.tf`, nothing in `.tfvars`
- **Pros:** Zero CLI flags.
- **Cons:** Per-environment values are embedded in code; PRs diff
  irrelevant environments; identifiers leak into git history.
- **Rejected because:** Loses the ability to plan one environment
  without rendering the others.

### Alternative C: Pull all variables from a vault at plan time
- **Pros:** No values in the repo at all.
- **Cons:** Chicken-and-egg (the vault is often provisioned by the
  same root); slows down plan; opaque diffs in code review.
- **Rejected because:** Operationally heavy for values that are not
  secret. Secrets are handled separately (ADR-0033).

## Consequences

- Adding an environment is a data change (one new `<env>.tfvars`, one
  new state backend record) plus a pipeline registration — no code
  change.
- Cross-cutting changes (project rename, egress IP change) happen in
  one `locals.tf` edit.
- Secrets stay out of `.tfvars`; OIDC-derived `TF_VAR_AZURE_*` carries
  identity at runtime.
- The two-layer split requires discipline: a value placed in the wrong
  layer (constant in tfvars, or per-env value in locals) is a future
  source of drift.

## Related

- ADR-0023 — Single-root layout that this strategy targets.
- ADR-0022 — OIDC providing pipeline-injected identity values.
- ADR-0035 — Feature flags configured through the per-env tfvars.

# ADR-0038: Pin Terraform Core and Major Provider Versions

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure / Databricks

## Context

Unpinned Terraform and provider versions produce two recurring failure
modes:

1. A CI run silently upgrades to a new major version with breaking
   changes, often discovered only after a failed plan or surprising
   diff.
2. Two operators running the same `terraform plan` locally see
   different plans because they have different provider versions
   installed.

Both are hard to debug and expensive in consulting time.

## General Principle

Pin **Terraform core** and **major provider versions** in code, and
pin the **CI runner's Terraform version** to match. Use pessimistic
constraints (`~> X.Y`) rather than exact pins, so security patches flow
through, but major upgrades require an explicit code change. Submodules
should declare provider sources without re-pinning versions, so the
root's constraint wins.

## Technology-Specific Application

**Terraform core** — pinned in `providers.tf`:

```hcl
terraform {
  required_version = "~> 1.11.0"
}
```

…and in CI input parameters so the same minor stream runs everywhere:

```yaml
# release pipeline input
tfVersion: '1.11.5'
```

**Provider versions** — pinned with pessimistic constraints in the root
`providers.tf`:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.52.0"
    }
  }
}
```

**Submodule provider declarations** — declare the source only, no
version, so the root constraint applies uniformly:

```hcl
# modules/<resource>/main.tf
terraform {
  required_providers {
    databricks = { source = "databricks/databricks" }
  }
}
```

### Constraint width

- `~> 3.0` on `azurerm` is broad (any 3.x). Tighten to `~> 3.116` (or
  similar) when a specific minor is known good and dropping a future
  minor's deprecation is undesirable.
- `~> 1.52.0` on the Databricks provider is narrow (patch only) —
  Databricks 1.x ships breaking minor bumps, so quarterly review is
  appropriate.
- `~> 1.11.0` on Terraform core lets in patch releases of the same
  minor; bump deliberately when ready.

### Trade-offs in this realisation

- The Terraform version is recorded in three places: `required_version`
  in HCL, the release pipeline input, and any account-level pipeline
  input. These can drift; pick one source of truth (typically the HCL)
  and reconcile on each upgrade.
- A local `terraform init -upgrade` can leap the pinned provider if a
  newer release falls within the constraint window; the resulting
  state mark can produce CI diffs. Communicate the intended constraint
  width.
- Patch-level constraints on a fast-moving provider impose quarterly
  upgrade work; budget for it.

## Alternatives Considered

### Alternative A: No version constraints (always `latest`)
- **Pros:** No stale version to chase; free upgrades.
- **Cons:** CI becomes non-deterministic; breaking-change PRs appear
  at random; bisection is hard.
- **Rejected because:** Unfit for any production path.

### Alternative B: Exact version pins (`version = "3.116.0"`)
- **Pros:** Maximum determinism.
- **Cons:** Every patch requires a PR; toil is high.
- **Rejected because:** Over-constraining; `~>` allows patches.

### Alternative C: `required_version` pinned in HCL, `latest` in CI
- **Pros:** Deterministic local, flexible CI.
- **Cons:** Reverse of what is wanted — CI should be the most
  deterministic, not the least.
- **Rejected because:** Wrong-way constraint.

## Consequences

- Plans are reproducible across CI and local when both use the matched
  Terraform version and the pinned providers.
- Major-version upgrades for AzureRM or Databricks are deliberate
  (require a constraint change) rather than silent.
- New contributors see required versions at the top of `providers.tf`.
- Multiple version-pin sites must be kept aligned across HCL and CI
  inputs; an upgrade is a multi-touch change.
- A local `terraform init -upgrade` can move state forward of CI
  unless contributors are aware.

## Related

- ADR-0034 — Personal Compute cluster policy that depends on the
  Databricks provider's `personal-vm` policy-family schema.
- ADR-0023 — Single-root layout where these constraints live.

# ADR-0023: Single-Root Terraform Layout with Per-Resource Modules

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure / Databricks

## Context

An Azure Databricks lakehouse is composed of a dozen related resources —
network, storage account, Key Vault, Databricks workspace, Unity Catalog
objects, optional Data Factory / SQL / Event Hub, log analytics, and so on.
The Terraform code could be organised as:

- One monolithic root with no submodules.
- One root module **per environment**, each duplicating the composition layer.
- A **single root** that composes per-resource child modules, parameterised
  per environment via `.tfvars` and per-environment state backends.

The decision is which layout to adopt as the platform default for a
multi-environment Azure Databricks lakehouse.

## General Principle

A multi-environment infrastructure stack should have **one source of truth
for composition** — what resources exist and how they wire together — and
**per-environment isolation only at the variable and state boundary**.
Composition belongs in code; environment-specific values belong in data.

This avoids both extremes: a single 1500-line root file (unreadable, no
reuse) and a per-environment root tree (composition copy-pasted across N
folders, drift inevitable).

## Technology-Specific Application

Adopt a **single Terraform root** that composes **per-resource child
modules** and selects environments via `-var-file` plus a per-env
backend init. A representative shape:

```
<root>/
  backend.tf          # azurerm backend (params injected at init)
  providers.tf        # azurerm + databricks providers
  locals.tf           # cross-environment constants
  variables.tf        # all input variables
  main.tf             # module composition
  imports.tf          # terraform import blocks (when migrating resources)
  modules/
    network/
    storage_account/
    key_vault/
    databricks_workspace/
    databricks_resources/
    data_factory/
    sql_server_and_db/
    event_hub/
    log_analytics_workspace/
    static_web_app/
  environments/
    dev.tfvars
    test.tfvars
    prod.tfvars
```

Each child module folder contains a small, predictable file set:

- `main.tf` (or a file named after the resource, e.g. `storage_account.tf`)
- `variables.tf`
- `outputs.tf`

Environment selection happens at two boundaries:

- `terraform init -backend-config=...` selects the per-env state account.
- `terraform plan -var-file=environments/<env>.tfvars` selects per-env values.

Module boundaries follow Azure resource boundaries — one Azure resource
type per module. This matches how operators reason about Azure (network,
storage, Key Vault, …) and keeps blast radius localised.

### Trade-offs in this realisation

- A typo in the wrong tfvars can plan against the wrong environment if the
  operator also points init at the wrong state account. Only pipeline
  convention prevents this; the file layout does not.
- The `imports.tf` file at the root invites large blast-radius
  `terraform import` runs; guardrails are operator discipline, not code.
- Copy-paste between modules (e.g. naming-default expressions) is a form
  of pseudo-coupling — fixing the pattern requires touching every module.

## Alternatives Considered

### Alternative A: One root module per environment
- **Pros:** Strong physical isolation; impossible to accidentally apply
  the dev plan to prod.
- **Cons:** Composition is duplicated N times; drift between environments
  creeps in; cross-cutting PRs become large.
- **Rejected because:** Per-environment state plus per-env tfvars already
  give blast-radius isolation; physical duplication of composition adds
  drift risk without commensurate gain.

### Alternative B: One monolithic root with no submodules
- **Pros:** No module variable plumbing.
- **Cons:** A single file becomes unreadable past a few hundred lines; no
  reuse; mental model collapses.
- **Rejected because:** Empirically painful at the scale of even a single
  lakehouse stack.

### Alternative C: External, versioned modules (Terraform Registry / private)
- **Pros:** Reuse across engagements; semver discipline; clear API.
- **Cons:** Releases must be cut for every change; debugging spans
  repos; client-specific quirks (naming, allow-lists, optional services)
  do not generalise cleanly until they have been seen across engagements.
- **Rejected because:** Premature externalisation; revisit once the same
  module shape has stabilised across two or more engagements.

## Consequences

- Composition lives in one `main.tf`; reading the root is enough to know
  what the stack contains.
- Each module follows the same shape, so adding a new resource is
  mechanical.
- Environment promotion is "change the tfvars and the backend" — a small,
  reviewable surface area.
- The single-root model relies on pipeline discipline to pair the right
  tfvars with the right backend; misconfiguration is possible.
- Because modules are local to the root, refactoring is cheap; the cost
  is paid later if/when a module needs to be reused outside this stack.

## Related

- ADR-0021 — AzureRM remote state backend (per-env state accounts).
- ADR-0024 — Per-environment `.tfvars` strategy that this layout depends on.
- ADR-0035 — Optional modules via feature flags on top of this layout.

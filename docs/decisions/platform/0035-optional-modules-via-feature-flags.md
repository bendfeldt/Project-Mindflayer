# ADR-0035: Optional Modules via Boolean Feature Flags

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure

## Context

Not every environment needs every resource. A development environment
may skip the SQL server to save cost. A test environment may skip the
documentation site. Some engagements never use Event Hub. Data Factory
is optional when ingestion is handled entirely by Databricks.

A single Terraform root (ADR-0023) needs a way to deploy a **superset**
of resources, with simple per-environment on/off control over the
optional ones.

## General Principle

Make optional modules **explicit and toggleable** in the root
composition, with a per-module boolean variable that gates the module.
The root file should make it visible at a glance which resources are
optional and which are always-on. Required modules carry no flag.

The price of this approach is a small idiomatic dance around `count`-ed
modules — accept it as the cost of keeping composition in one place.

## Technology-Specific Application

Guard each optional module with a `count` expression bound to a boolean
tfvar:

```hcl
module "data_factory" {
  count  = var.deploy_datafactory ? 1 : 0
  source = "./modules/data_factory"
  # ...
}

module "sql_server" {
  count  = var.deploy_sql_server ? 1 : 0
  source = "./modules/sql_server_and_db"
  # ...
}

module "event_hub" {
  count  = var.deploy_event_hub ? 1 : 0
  source = "./modules/event_hub"
  # ...
}

module "static_web_app" {
  count  = var.deploy_documentation_site ? 1 : 0
  source = "./modules/static_web_app"
  # ...
}

module "network" {
  count  = var.enable_vnet ? 1 : 0
  source = "./modules/network"
  # ...
}
```

Required modules (`storage_account`, `key_vault`, `databricks_workspace`,
`databricks_resources`) carry no flag and are always provisioned.

Downstream references to optional modules use the
`length(module.foo) > 0 ? module.foo[0].x : null` pattern:

```hcl
sql_server_id = length(module.sql_server) > 0 ? module.sql_server[0].id : null
```

### Trade-offs in this realisation

- Every downstream reference to an optional module needs the
  `length(...)` dance. Easy to forget; produces confusing errors when
  missed.
- Flipping a flag from `true` to `false` schedules a destroy for the
  module's resources. On production data, that is a cliff. Operators
  must read `terraform plan` carefully on any flag change.
- Flags are independent booleans — there is no encoding of invalid
  combinations (e.g. "service X requires service Y"). Coupling is left
  to operator discipline.
- A network flag that disables the network module while a workspace
  flag still expects VNet injection produces an apply-time failure
  rather than a plan-time error.

## Alternatives Considered

### Alternative A: `for_each` over a set of enabled module names
- **Pros:** Single collection drives enable/disable.
- **Cons:** Terraform's module `for_each` does not compose with
  different module schemas; would require a wrapper module per
  resource.
- **Rejected because:** Over-engineering for a small number of optional
  modules.

### Alternative B: Separate root modules per "flavor"
- **Pros:** No conditional plumbing.
- **Cons:** Explodes into 2^N combinations of identical-but-not-quite
  roots; contradicts the single-root design.
- **Rejected because:** Violates ADR-0023.

### Alternative C: Workspaces + conditionals inside modules
- **Pros:** Constant module count.
- **Cons:** Hides the deploy shape inside modules; harder to read.
- **Rejected because:** Composition shape should be visible at the root,
  not buried.

## Consequences

- The root composition is self-documenting; `count` lines reveal the
  optional surface.
- A new environment can start minimal and opt in per module.
- Removing a module from a live environment is a one-line tfvars change
  — review `terraform plan` carefully before applying.
- The `length(module.*) > 0 ? ... : null` pattern propagates to every
  consumer; this is intrinsic to `count`-ed modules in Terraform.
- Cross-module dependency invariants are not encoded; document them in
  comments or ADRs and enforce in code review.

## Related

- ADR-0023 — Single-root layout that this composition style targets.
- ADR-0024 — Per-environment tfvars where the boolean flags live.

# ADR-0034: Personal-Compute Cluster Policy with 60-Minute Auto-Termination

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks / Compute governance

## Context

Interactive Databricks clusters left running overnight are one of the
largest cost leaks in any Databricks engagement. Databricks ships a
built-in `personal-vm` cluster policy family that gives each user a
small, isolated interactive cluster, but the default does not cap
auto-termination, so it drifts in practice.

The goal is for every developer interactive cluster to auto-terminate
after a bounded idle period without requiring users to remember to set
it.

## General Principle

For developer-facing interactive compute, **inherit the platform's
maintained policy family and override only what is needed** — typically
auto-termination. Avoid hand-rolling cluster policies from scratch
because they fall behind upstream changes; avoid leaving the default
unconstrained because cost discipline depends on a hard cap.

A 60-minute auto-termination value is a defensible default: long enough
that legitimate long-running cells (model training, large
materialisations) survive a brief detach, short enough that an
overnight forgotten session does not produce a multi-hour bill.

## Technology-Specific Application

Inherit the Databricks-provided `personal-vm` policy family and override
just the auto-termination setting:

```hcl
locals {
  personal_vm_override = {
    "autotermination_minutes" = {
      "type"   = "fixed"
      "value"  = 60
      "hidden" = false
    }
  }
}

resource "databricks_cluster_policy" "personal_compute" {
  policy_family_id                   = "personal-vm"
  policy_family_definition_overrides = jsonencode(local.personal_vm_override)
  name                               = "Personal Compute"
}
```

Job clusters terminate on job completion and are typically left
unconstrained by this policy. Shared all-purpose clusters are usually
not provisioned by default — add separate policies if/when they are
introduced.

### Trade-offs in this realisation

- `type: "fixed"` means developers cannot override the 60-minute value,
  even when a legitimate long-running case exists. Provide a separate
  policy for those cases rather than relaxing the default.
- The policy is workspace-scoped; a new workspace needs its own policy
  resource.
- If Databricks renames the `personal-vm` policy family or changes its
  schema, this resource fails on apply. Pinning the Databricks
  provider version (ADR-0038) limits the blast radius.

## Alternatives Considered

### Alternative A: No cluster policy (Databricks defaults)
- **Pros:** Zero configuration.
- **Cons:** Auto-termination defaults to 120 minutes and can be
  disabled by users; large cost exposure.
- **Rejected because:** Cost discipline is the entire point.

### Alternative B: Custom policy written from scratch
- **Pros:** Full control over every parameter.
- **Cons:** Requires maintenance every time Databricks adds a policy
  field; easy to fall behind recommendations.
- **Rejected because:** The maintained policy family already encodes
  the recommended baseline; inherit and override.

### Alternative C: Shorter auto-termination (e.g., 20 minutes)
- **Pros:** Cheaper.
- **Cons:** Long-running cells (Photon materialisations, training) can
  cause surprise terminations mid-execution, costing more developer
  time than is saved on cost.
- **Rejected because:** 60 minutes is the empirical sweet spot.

### Alternative D: Shared interactive cluster + SQL Warehouse only
- **Pros:** Maximum cost efficiency in dev.
- **Cons:** Shared state, noisy-neighbour issues, no per-user isolation.
- **Rejected (default):** Complementary rather than substitutive.
  Personal compute and shared SQL Warehouses can co-exist.

## Consequences

- Every developer who spins up a personal cluster gets a 60-minute
  auto-terminate without opting in.
- The policy tracks Databricks upstream — when Microsoft adds a field
  to the policy family, it is inherited automatically.
- Auto-termination remains visible in the UI, so users understand why
  a cluster shut down.
- Job clusters and any shared all-purpose clusters need their own
  governance.
- Workspace-scoped — duplicate the resource per new workspace.

## Related

- ADR-0017 — Databricks compute defaults (this ADR is the
  cluster-policy realisation of the dev-tier compute model in 0017).
- ADR-0038 — Pinned Databricks provider version that protects against
  upstream schema breakage.

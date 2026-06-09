# ADR-0036: Dual CI/CD Pipelines — GitHub Actions and Azure DevOps

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Cross-cutting (CI/CD)

## Context

Consultancy engagements often span both GitHub (typical for internal and
open-source tooling) and Azure DevOps (a common enterprise standard).
Either platform can deploy the same Terraform root, but the YAML
syntaxes and the shape of the "plan → approve → apply" flow differ.

Forcing one CI platform constrains the engagement; supporting both
keeps the deploy logic portable but doubles surface area.

## General Principle

When an engagement is likely to span multiple CI platforms, support
**both pipeline trees with feature parity** rather than picking one and
later rewriting. Keep the **Terraform contract identical** across
pipelines (same backend conventions, same variable names, same OIDC
auth) so that the platform difference shows up only in the YAML entry
points, not in the deploy logic itself.

If the engagement is firmly on one platform from the start, this ADR
does not apply — pick one, skip the cost of dual maintenance.

## Technology-Specific Application

Maintain two parallel pipeline trees. The naming below is illustrative;
adapt to local conventions.

**GitHub Actions:**

- `.github/workflows/build.yml` — publishes a build artifact.
- `.github/workflows/<stack>-release.yml` — per-env release workflow.
- `.github/workflows/<stack>-destroy.yml` — per-env destroy workflow.
- `.github/workflows/terraform_deploy.yml` — reusable per-env deploy.
- `.github/workflows/terraform_destroy.yml` — reusable per-env destroy.
- `.github/actions/release/{plan,apply}/action.yml` — composite actions.
- `.github/actions/destroy/{plan,apply}/action.yml` — composite actions.

**Azure DevOps:**

- `<ado>/pipelines/ci/build.yml`
- `<ado>/pipelines/azure-pipeline-terraform-release.yml`
- `<ado>/pipelines/azure-pipeline-terraform-destroy.yml`
- `<ado>/pipelines/cd/release_modules/{plan,approval,apply,clean_up}.yml`
- `<ado>/pipelines/cd/destroy_modules/{plan,destroy,clean_up}.yml`
- Optional `<ado>/pipelines/cd/import_modules/terraform_import.yml`.

Both pipelines:

- Use OIDC federated identity (ADR-0022) — no client secrets.
- Use the AzureRM remote state backend (ADR-0021) with the same per-env
  state account convention.
- Align variable names across platforms (e.g. `azureRg`,
  `tfStorageName`, `tfStorageContainer`, `tfStateFileName`, `tfVars`,
  `artifactName`).

### Trade-offs in this realisation

- Two pipeline trees to keep in sync; a fix on one can be forgotten on
  the other.
- Pipeline-specific bugs have double the surface area.
- Iteration on shared steps requires editing both.
- A `terraform_import` flow may exist on one platform and not the
  other — divergence is acceptable for low-frequency operator actions
  but should be documented.
- `TF_LOG` levels differ between release and destroy pipelines on
  GitHub Actions in some setups; align these or accept that destroy
  logs may be more verbose.

## Alternatives Considered

### Alternative A: GitHub Actions only
- **Pros:** One platform to maintain; modern composite actions.
- **Cons:** Some clients mandate Azure DevOps for deployment governance.
- **Rejected because:** Removes platform flexibility; revisit when the
  engagement is firmly on one platform.

### Alternative B: Azure DevOps only
- **Pros:** Native Azure integration; mature approval gates.
- **Cons:** Engagement-internal workflows often live in GitHub.
- **Rejected because:** Same reason in reverse.

### Alternative C: A single generic CI spec (Dagger, Earthly, etc.)
- **Pros:** DRY.
- **Cons:** Extra tool; neither GitHub nor ADO has first-class support;
  OIDC plumbing remains platform-specific.
- **Rejected because:** Cost not justified.

### Alternative D: GitHub Actions mirrored to ADO via sync
- **Pros:** Single source of truth.
- **Cons:** ADO YAML is materially different from GitHub Actions — a
  working "mirror" is a translator, not a sync.
- **Rejected because:** Complexity without benefit.

## Consequences

- The engagement can move between CI platforms (or run both in
  parallel) without rewriting deploy logic.
- Both platforms see the same Terraform contract, reducing
  "works-on-X-broken-on-Y" regressions.
- Per-platform approval gates and environment protection rules are
  reused without change.
- Maintenance cost is roughly 1.5× a single platform — fixes,
  upgrades, and pattern changes apply twice.
- Treat the two trees as a single deliverable in code review: a
  GitHub-only fix that does not have an ADO counterpart is incomplete.

## Related

- ADR-0021 — AzureRM remote state backend used by both pipelines.
- ADR-0022 — OIDC federated identity used by both pipelines.
- ADR-0037 — Agent IP allow-listing applied symmetrically by both.

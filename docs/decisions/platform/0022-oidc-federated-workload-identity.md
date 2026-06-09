# ADR-0022: Authenticate CI/CD via OIDC Federated Workload Identity

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Cross-cutting (Terraform / Azure / Databricks CI/CD)

## Context

Deploy pipelines (Terraform plan/apply/destroy, metastore provisioning,
post-deploy configuration) need to authenticate to Azure as a principal
with sufficient permission to manage the resource group, storage account,
Key Vault, Databricks workspace, and Unity Catalog objects.

Historically, those credentials lived as long-lived client secrets stored
in CI variable groups. That pattern produced two persistent problems:
secrets had to be rotated manually, and anyone with read access to the
variable group could exfiltrate them.

## General Principle

CI/CD pipelines should authenticate to the cloud using **short-lived,
identity-federated tokens** rather than long-lived client secrets.
The pipeline's OIDC issuer asserts the workflow's identity (repo, ref,
environment) directly to the cloud's identity provider, which exchanges
that assertion for a scoped, short-lived access token. No secret is ever
stored.

This applies to GitHub Actions, Azure DevOps, GitLab CI, and any other
runner that supports OIDC token issuance — the cloud-side configuration
differs, but the principle is the same.

## Technology-Specific Application

On Azure, configure an Entra ID app registration (or user-assigned managed
identity) with one **federated credential** per workflow / environment
combination. The federated credential's subject claim must match the
runner's identity exactly, e.g. `repo:<org>/<repo>:environment:<env>` for
GitHub Actions, or the matching ADO subject pattern for Azure DevOps.

The pipeline:

1. Requests an OIDC token from the platform (e.g. `permissions: id-token: write` in GitHub Actions).
2. Calls `azure/login` (or the ADO `AzureCLI@2` task with workload identity)
   with `client-id` / `tenant-id` / `subscription-id`.
3. Exports `ARM_USE_OIDC=true` plus `ARM_CLIENT_ID` / `ARM_TENANT_ID` /
   `ARM_SUBSCRIPTION_ID` so the AzureRM and Databricks Terraform providers
   reuse the same identity.

The Databricks provider authenticates with `auth_type = "azure-cli"` against
both the workspace host and the account host
(`https://accounts.azuredatabricks.net`), reusing the federated `az login`
from the same step. This keeps a single auth identity across `terraform`,
`az`, and the Databricks provider.

### Trade-offs in this realisation

- Federated credentials must be created in the app registration ahead of
  time with the correct subject claim — a typo silently produces a
  generic auth failure.
- Local developer plans do not get OIDC; humans `az login` interactively,
  so the local and CI auth paths diverge slightly.
- `azure-cli` auth for the Databricks provider requires the `az login`
  state to persist between steps in the same job. Splitting plan and apply
  across separate jobs breaks that assumption.

## Alternatives Considered

### Alternative A: Client secret in a CI secret store
- **Pros:** Works everywhere; familiar; no federation setup.
- **Cons:** Long-lived credential requiring rotation; secret leakage
  grants subscription-wide access until rotated; weak forensics.
- **Rejected because:** Industry direction is away from long-lived secrets;
  OIDC federation is now first-class on every major CI platform.

### Alternative B: Managed identity on a self-hosted runner
- **Pros:** No credential at all; identity bound to the runner VM.
- **Cons:** Requires self-hosted runner infrastructure (cost,
  maintenance, patching); incompatible with hosted runners.
- **Rejected because:** Cost and ops outweigh the benefit when a hosted
  runner with OIDC achieves the same "no stored secret" property.

### Alternative C: Mixed — OIDC on one platform, secrets on the other
- **Pros:** Pragmatic; use OIDC where it is easy.
- **Cons:** Inconsistent security posture across pipelines; two threat
  models to reason about.
- **Rejected because:** OIDC is supported on every modern CI platform;
  using it everywhere is simpler than tracking divergence.

## Consequences

- No long-lived secrets to rotate, store, or accidentally print.
- Identity is bound to the workflow path and ref pattern via the
  federation credential — a fork or unrelated workflow cannot impersonate
  the identity.
- The same `ARM_*` variable contract works for `terraform`, `az`, and the
  Databricks provider, reducing per-step configuration drift.
- Federated credentials must be configured per environment / branch; the
  app-registration side becomes the new place where misconfiguration shows
  up.
- If the OIDC `permissions:` block is removed from a workflow, token
  issuance silently fails; the resulting error message can be cryptic.
- Federated identity satisfies many "no embedded secrets" compliance
  controls (SOC2 CC6.1, ISO 27001 A.9.4.3) and produces an audit trail in
  Entra ID for each token issuance.

## Related

- ADR-0021 — AzureRM remote state backend used by the same pipelines.
- ADR-0036 — Dual CI/CD pipelines applying this auth pattern to both
  GitHub Actions and Azure DevOps.
- ADR-0037 — Agent IP allow-listing during plan/apply, complementary to
  the OIDC identity model.

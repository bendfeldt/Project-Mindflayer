# ADR-0037: Agent IP Allow-Listing on Storage / Key Vault / Event Hub During Plan and Apply

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Terraform on Azure / Networking / CI

## Context

When a lakehouse is VNet-injected (ADR-0025) with service endpoints
(ADR-0026) and firewalls on storage / Key Vault / Event Hub, the
Terraform agent itself is **not** in the customer VNet. Hosted runners
(GitHub-hosted, Microsoft-hosted ADO agents) have ephemeral public IPs.

Without intervention, `terraform plan` (which reads state and resources)
and `terraform apply` (which provisions and configures them) would be
blocked by the firewall on those PaaS resources.

## General Principle

A short-lived, **transient IP allow-list entry** added by the pipeline
just before plan/apply and removed immediately after is preferable to
either (a) running a permanently allow-listed self-hosted runner inside
the network, or (b) weakening the PaaS firewall to `default_action = Allow`.

The pipeline owns the firewall mutation and is responsible for cleaning
up after itself. Terraform code uses `lifecycle { ignore_changes }` on
the relevant fields so it does not fight the pipeline-driven churn.

## Technology-Specific Application

Before `terraform init` / `plan` runs, a pipeline step:

1. Resolves the agent's public IP (e.g. via `https://api.ipify.org` or
   a similar lookup).
2. Adds it to every storage account in the resource group
   (`Add-AzStorageAccountNetworkRule`).
3. Adds it to every Key Vault in the resource group
   (`Add-AzKeyVaultNetworkRule`).
4. Adds it to every Event Hub namespace (typically via
   `Set-AzEventHubNetworkRuleSet`).

A symmetric teardown step removes the agent IP after apply (and on
failure paths) so the firewall returns to its baseline.

A mode toggle (e.g. `agentNetworkAccessMode: "ip" | "public"`) lets
operators switch between IP allow-listing and temporarily opening
`DefaultAction Allow`. Production pipelines should always use `"ip"`.

To prevent Terraform from reverting the pipeline's changes:

```hcl
# storage account network rules
lifecycle {
  ignore_changes = [virtual_network_subnet_ids, ip_rules]
}

# key vault
lifecycle {
  ignore_changes = [network_acls]
}
```

### Trade-offs in this realisation

- Public-IP-resolution dependencies (`api.ipify.org`, `ipinfo.io`, etc.)
  are external; rate limits or outages block every pipeline run.
  Provide a fallback or self-host the lookup.
- A failed pipeline run can leave a stale allow-list entry; periodic
  reconciliation or a teardown that runs `always()` is required.
- `ignore_changes` on `ip_rules` means an operator who tries to add a
  permanent IP rule **in Terraform** will be ignored. Permanent rules
  must be applied out-of-band or by removing `ignore_changes`.
- Some Event Hub cmdlets **replace** the entire rule set rather than
  patch it — the pipeline must reconcile with whatever already exists,
  or it will clobber unrelated entries.
- Hosted runners can change IP between resolution and `init` on rare
  network paths; the failure mode is observable but uncommon.

## Alternatives Considered

### Alternative A: Self-hosted runner inside the VNet
- **Pros:** No firewall gymnastics; runner is already in allow-listed
  subnets.
- **Cons:** Self-hosted runners require a VM/container, patching, and
  registration secrets; abandons the OIDC model adopted in ADR-0022 in
  favour of a long-lived runtime identity.
- **Rejected because:** Cost and ops overhead outweigh the benefit at
  typical pipeline cadence.

### Alternative B: `DefaultAction = Allow` with bypass=AzureServices
- **Pros:** Simpler — no transient IP adds.
- **Cons:** Storage / Key Vault accept any public IP unless explicitly
  denied; weakens the security baseline.
- **Rejected because:** Defeats the purpose of firewalled PaaS.

### Alternative C: Bastion VM that runs Terraform
- **Pros:** Terraform runs inside the network boundary.
- **Cons:** Adds a VM to maintain; SSH/serial access widens the attack
  surface.
- **Rejected because:** Not justified at typical scale.

### Alternative D: Fixed egress IP for the hosted runner (custom runner image + Azure)
- **Pros:** Static IP, no lookup needed.
- **Cons:** Requires custom runner infrastructure — equivalent cost to
  Alternative A.
- **Rejected because:** Same reasons as A.

## Consequences

- Vanilla hosted runners can deploy into a firewalled lakehouse without
  any persistent allow-list entry.
- The mode toggle gives an explicit escape hatch for emergencies.
- `ignore_changes` keeps Terraform plans clean — pipeline-driven
  firewall churn does not show up as drift.
- The pipeline owns firewall state during the run; failed runs leave
  stale entries that must be reconciled.
- The IP-resolution external dependency is a load-bearing component of
  the deploy path; treat it as such.
- The transient allow-and-remove flow leaves an audit trail in the
  Azure Activity Log, which is appropriate for ISO 27001 A.12.4.1.
- `agentNetworkAccessMode = "public"` should be disabled in any
  environment subject to data-classification controls.

## Related

- ADR-0022 — OIDC federated identity that this pattern complements.
- ADR-0025 — VNet injection that creates the firewall premise.
- ADR-0026 — Service endpoints firewall model.
- ADR-0036 — Dual CI/CD pipelines that both implement this pattern.

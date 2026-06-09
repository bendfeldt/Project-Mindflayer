# ADR-0026: Use Service Endpoints (not Private Endpoints) for Databricks-to-PaaS Traffic

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Networking

## Context

Once a Databricks workspace is VNet-injected (ADR-0025), traffic from
clusters to ADLS / Key Vault / Event Hub still needs a non-public path.
Azure offers two patterns:

- **Service Endpoints** — extend the VNet identity to the PaaS resource
  over the Azure backbone. No new IP, no new DNS, but only reachable from
  within Azure VNets.
- **Private Endpoints (Private Link)** — inject a NIC into the VNet for
  each PaaS resource, requiring private DNS zones and a per-endpoint cost.

The choice depends on whether on-premises connectivity (ExpressRoute / VPN)
is in scope and whether auditors require PaaS resources to be entirely
unreachable from the public internet.

## General Principle

When a Databricks-on-Azure deployment has **no on-premises connectivity
requirement** and the security baseline accepts publicly resolvable PaaS
endpoints (with firewalled access), **service endpoints** are the
default network-access pattern: lower cost, no DNS to maintain, fewer
moving parts.

When either of those preconditions changes — on-prem reach is needed, or
auditors require "no public IP exposure on data-plane PaaS" — switch to
**private endpoints**, accept the DNS-zone overhead, and supersede this
ADR with a Private-Link variant.

## Technology-Specific Application

Configure both Databricks subnets with the relevant service endpoints:

```hcl
service_endpoints = [
  "Microsoft.Storage",
  "Microsoft.KeyVault",
  "Microsoft.EventHub",
]
```

Lock down the corresponding PaaS resource firewalls to those subnets plus
an explicit IP allow-list (see ADR-0037 for how the deploy agent's IP is
managed transiently):

- **Storage account** — `azurerm_storage_account_network_rules` with
  `virtual_network_subnet_ids = [public_subnet, private_subnet, ...]`
  and `ip_rules` containing the operator/agent IPs.
- **Key Vault** — `network_acls` with the same subnet list and IP rules.
- **Event Hub** — equivalent subnet/IP allow-list pattern.

For Databricks Serverless (which runs in Microsoft-managed VNets, not the
customer VNet), additionally allow the Network Connectivity Configuration
(NCC) worker subnet IDs supplied via a per-environment list variable.

### Trade-offs in this realisation

- `default_action = "Allow"` on storage network rules paired with a
  bypass and IP rules is a documented compromise. A stricter `Deny`
  default requires a complete IP/subnet inventory at apply time, which
  the agent IP allow-listing flow (ADR-0037) handles imperfectly.
- The Serverless NCC subnet list goes stale silently when Databricks
  rolls a new region — schedule periodic reviews.
- Adding a new PaaS service later requires extending the
  `service_endpoints` list **and** the new resource's network rules — easy
  to forget on the first half of that pair.

## Alternatives Considered

### Alternative A: Private Endpoints + custom DNS zones
- **Pros:** Strongest isolation; works for on-prem traffic over
  ExpressRoute / VPN; PaaS resources can be made unreachable from the
  public internet.
- **Cons:** Requires private DNS zones per service; per-endpoint cost;
  more state to manage; broken Databricks connectivity if DNS zones drift.
- **Rejected because:** Heavier than required when on-prem reach is not
  in scope. Promote to default when those conditions change.

### Alternative B: Public access only with IP firewall
- **Pros:** Simplest; no VNet config.
- **Cons:** Cluster IPs are not stable; would force a wide IP allow-list
  or `default_action = "Allow"`.
- **Rejected because:** Defeats the purpose of VNet injection.

### Alternative C: Hybrid — service endpoints today, private endpoints later
- **Pros:** Leaves the door open.
- **Cons:** Not a separate alternative — it is exactly the migration path
  this ADR's revisit trigger captures.

## Consequences

- Zero per-endpoint cost; service endpoints are free.
- No DNS to maintain; no risk of DNS drift breaking workspace
  connectivity.
- Backbone-only traffic between Databricks subnets and storage / Key
  Vault / Event Hub satisfies most data-in-transit-isolation expectations
  (ISO 27001 A.13.2.1).
- Auditors who require "no public IP exposure on PaaS resources" will
  not be satisfied — service endpoints leave the resource publicly
  resolvable. Captured as the explicit revisit trigger.
- Any future on-prem (ExpressRoute / VPN) requirement triggers a redesign.

## Related

- ADR-0025 — VNet injection that this access pattern depends on.
- ADR-0027 — NAT Gateway egress, complementary to inbound service endpoints.
- ADR-0032 — Key Vault RBAC and firewall hardening.
- ADR-0037 — Agent IP allow-listing during plan/apply.

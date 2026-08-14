---
name: promote-adr
description: Generalize an accepted repository ADR for promotion into the toolkit decision set.
---

# Promote ADR

Read [promotion mechanics](references/promotion.md).

1. Select an accepted repository ADR and inspect its dependencies.
2. Remove client names, resource identifiers, regions, subscriptions, and engagement-only constraints.
3. Decide whether the result is a durable toolkit decision or normative guidance. Promote policy to guidance; reserve toolkit ADRs for repository design decisions.
4. Check for conflicts and choose the next number only in the destination checkout.
5. Preview the generalized diff and ask for approval before writing.
6. Update the central manifest if the promoted file is distributable.
7. Validate links and references. Never commit or publish automatically.

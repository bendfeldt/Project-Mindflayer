# ADR-0003: Thin Repo Templates (~70 Lines) with Version Headers

**Status:** Accepted
**Date:** 2026-03-01
**Deciders:** Michael Bendfeldt

## Context

Each client repo needs an `AGENTS.md` that describes the platform, build commands, safety
rules, and branching conventions. Early versions of these templates were comprehensive
(200+ lines), covering everything that could possibly be relevant. This caused two problems:

1. Most content was irrelevant to a given client, adding noise that degraded agent focus
2. Installed templates drifted from the source silently — no way to know when the
   toolkit had improved and the installed version was stale

## Decision

We will keep repo templates thin (~70 lines) containing only client-specific, platform-
specific content. Global standards (coding style, compliance awareness, stack preferences)
belong in the global `~/.claude/CLAUDE.md`, not in repo templates.

All templates will carry an HTML comment version header on line 1:

```
<!-- template: AGENTS-fabric | version: 1.0.0 | updated: 2026-03-24 -->
```

`tools/check-template-update.sh` reads this header and compares it against the current
source template to detect drift.

## Alternatives Considered

### Alternative A: Comprehensive templates (200+ lines)
- **Pros:** Everything in one file; no layering to understand; works even if the global config is missing
- **Cons:** Content duplication across all client repos; global updates require updating every installed template; agent reads irrelevant content for every interaction

### Alternative B: Generated templates (templating engine or installer interpolation)
- **Pros:** Could inject global context at install time without duplication
- **Cons:** Introduces a build step; generated files are harder to read and diff; no standard Bash templating that works cross-platform without extra dependencies

### Alternative C: Thin templates + version headers (chosen)
- **Pros:** Each file focuses on client context only; global updates happen once in `~/.claude/CLAUDE.md`; version headers give visibility into drift without forcing automatic updates
- **Cons:** Requires understanding the two-layer model; missing global config degrades agent context

## Consequences

### Positive
- Templates are fast to scan and easy to customize per client
- Drift detection is explicit and opt-in — the engineer chooses when to pull template updates
- Reducing template size improves agent focus on client-relevant context

### Negative
- A repo with only `AGENTS.md` and no global config installed gives the agent less context
- The version header must be manually maintained when templates are updated

### Risks
- If the version header format changes, `check-template-update.sh` must be updated accordingly

## References

- `/templates/AGENTS-*.md` — the four platform templates
- `/tools/check-template-update.sh` — drift detection script

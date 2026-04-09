# ADR-0002: SKILL.md Open Standard for Cross-Agent Skills

**Status:** Accepted
**Date:** 2026-03-01
**Deciders:** Michael Bendfeldt

## Context

Claude Code has a native slash-command mechanism for reusable workflows. Other agents
(Codex, Gemini, Cursor) have no equivalent — or have proprietary formats. As a consultant
operating across all these agents in different client repos, I needed a way to package
reusable workflows (ADRs, Terraform scaffolding, Kimball modeling) that work regardless
of which agent is active in the repo.

## Decision

We will define skills using the `SKILL.md` open standard: a Markdown file with a YAML
frontmatter block (`name`, `description`) followed by instructions the agent reads and
executes. Skills are stored in `~/.claude/skills/<name>/SKILL.md` for Claude Code
(loaded as slash commands) and referenced directly by other agents when the user
asks to use them by name.

## Alternatives Considered

### Alternative A: Claude-only slash commands
- **Pros:** Native Claude Code feature; no custom format needed; full IDE integration
- **Cons:** Completely unusable in Codex, Gemini, Cursor; breaks the multi-agent model

### Alternative B: Agent-specific skill files per tool
- **Pros:** Each agent gets its native format with maximum feature use
- **Cons:** Every skill must be duplicated and maintained in 3–5 formats; drift is inevitable; onboarding cost is high

### Alternative C: SKILL.md open standard (chosen)
- **Pros:** One file per skill; human-readable Markdown that any agent can interpret; loads natively as a Claude Code slash command while remaining accessible to other agents as a plain instruction file
- **Cons:** Loses agent-specific features (e.g. Claude tool_use annotations, Copilot prompt metadata); requires agents to interpret the skill description correctly rather than having native invocation

## Consequences

### Positive
- A skill written once works in all supported agents
- Skills are plain Markdown — readable, diffable, version-controlled with no binary formats
- The `setup-repo` installer copies skills to the correct location for each agent automatically

### Negative
- Agent-specific workflow features (structured tool calls, context window management hints) cannot be expressed in a portable format
- Skill invocation by non-Claude agents relies on the agent understanding the SKILL.md instructions via natural language, not a formal invocation mechanism

### Risks
- If agents diverge in how they interpret Markdown instruction files, skill behaviour may differ across agents — mitigated by keeping skill instructions explicit and imperative

## References

- `/skills/` — source directory for all toolkit skills
- `/skills/adr/SKILL.md`, `/skills/kimball-model/SKILL.md`, etc. — concrete examples

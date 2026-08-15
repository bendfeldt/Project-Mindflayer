# Consumer extensions

`AGENTS.md` is the cross-consumer project contract. Consumer-specific
extensions belong in native discovery locations only when they cannot be
expressed portably.

## Claude project extensions

- Put repeatable cross-project workflows in skills.
- Put explicit project-only workflows in `.claude/commands/`.
- Put isolated, narrowly scoped roles in `.claude/agents/`.
- Put deterministic lifecycle checks in hooks only when permissions or shared
  validation scripts cannot enforce the requirement.
- Put topic-specific guidance in `.claude/rules/`. Use `paths` frontmatter so a
  rule loads only for matching files; a rule without `paths` loads at startup.

Example path-scoped rule:

```markdown
---
paths:
  - "**/*.test.ts"
---

- Use the repository's existing test fixtures.
```

Do not store general policy, duplicated `AGENTS.md` content, or instructional
README files in runtime discovery directories. Add a native extension only
after the project has a concrete recurring need for it.

## Cursor and Copilot scoped instructions

Cursor reads root and nested `AGENTS.md` files directly. Use
`.cursor/rules/<name>.mdc` only when path patterns, relevance-based loading, or
manual invocation are required. Plain `.md` files in `.cursor/rules/` are not
rules.

Copilot reads root `AGENTS.md` directly. Use
`.github/instructions/<name>.instructions.md` only for path-specific behavior.
Do not duplicate repository-wide policy in `.github/copilot-instructions.md`.

## Hooks and portability

Hooks are consumer-specific adapters, not sources of policy. Prefer a shared
repository script or CI check, then let a hook invoke that deterministic
control where immediate feedback is useful. Avoid common-word triggers and
semantic routing that can fire accidentally.

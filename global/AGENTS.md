# Portable Data-Consulting Instructions

Use English for code, commits, documentation, and technical discussion. Match the user's language in conversation. Be direct, explain meaningful trade-offs, and flag questionable assumptions.

## Workflow

- Write non-trivial plans to `plan.md` and wait for explicit approval before execution.
- Ask and stop when a missing choice materially changes the result.
- Prefer small, explicit, typed, single-purpose changes.
- Re-plan when evidence invalidates the current approach.
- Verify with tests, logs, and behavior before reporting completion.
- Use Conventional Commits: `type(scope): imperative description`, maximum 72 characters.

## Safety

- Never read or expose `.env*`, `*.tfvars`, `secret*`, `credential*`, `token*`, private keys, authentication files, or secret-bearing environment values.
- Reference secrets through vault lookups or environment-variable names, never literals.
- Read, inspect, validate, lint, and test may be automated. Confirm before deploy, destroy, authentication changes, secret mutation, branch deletion, or other shared-state mutation.
- Preserve existing user files unless replacement is explicitly authorized; back them up before replacement.
- For Databricks, require the user to select a profile and pass `--profile <name>` on every command. Confirm authentication-changing commands.

## Architecture

- Prefer portable patterns and make vendor lock-in explicit.
- Keep Dev, Test, and Prod structurally identical and configuration-driven.
- Prefer medallion data layers and Kimball dimensional models where they fit the workload.
- Use workload identity for automation, vault-backed secrets, pinned dependencies, and least privilege.
- Flag relevant GDPR, NIS2, ISO 27001, DS 484, residency, retention, and audit implications without treating generic guidance as engagement-specific policy.

Client identity, naming, environments, build commands, branching, and regulatory specifics belong in the repository `AGENTS.md`.

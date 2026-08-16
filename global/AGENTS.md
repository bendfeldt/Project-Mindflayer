# Portable Data-Consulting Instructions

Use English for code, commits, documentation, and technical discussion. Match the user's language in conversation. Be direct, explain meaningful trade-offs, and flag questionable assumptions.

## Workflow

- Write every non-lookup task plan to `plan.md` and wait for explicit approval before execution.
- Ask and stop when a missing choice materially changes the result.
- Keep the requested scope; prefer small, explicit, typed, single-purpose changes.
- Re-plan when evidence invalidates the current approach.
- Verify with tests, logs, and behavior before reporting completion.
- Use Conventional Commits: `type(scope): imperative description`, maximum 72 characters.

## Safety

- Never read or expose `.env*`, `*.tfvars`, `secret*`, `credential*`, `token*`, private keys, authentication files, or secret-bearing environment values.
- Reference secrets through vault lookups or environment-variable names, never literals.
- Read, inspect, validate, lint, and test may be automated. Confirm before deploy, destroy, authentication changes, secret mutation, branch deletion, or other shared-state mutation.
- Preserve existing user files unless replacement is explicitly authorized; back them up before replacement.
- For Databricks, require the user to select a profile and pass `--profile <name>` on every command. Confirm authentication-changing commands.

## Routing

- Use `setup-repo` for repository onboarding, `engineering-auditor` for evidence-based cross-domain audits, `terraform-scaffold` for Terraform structure, and `kimball-model` for dimensional modeling.
- Prefer portable, configuration-driven patterns; make vendor lock-in explicit and keep Dev, Test, and Prod structurally identical.
- Prefer workload identity, vault-backed secrets, pinned dependencies, and least privilege.
- Flag relevant compliance, residency, retention, and audit implications without inventing engagement policy.

Client identity, naming, environments, build commands, branching, and regulatory specifics belong in the repository `AGENTS.md`.

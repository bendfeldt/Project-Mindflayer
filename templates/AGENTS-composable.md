# Project Instructions

<!-- template: AGENTS | version: 5.0.0 -->

## Repository identity

- **client:** {CLIENT_NAME}
- **project types:** {PROJECT_TYPES}
- **technologies:** {TECHNOLOGIES}
{RESOURCE_PREFIX_LINE}

## Project contract

- Add only verified repository-specific commands, naming, environments, regions, and architecture constraints here; do not infer missing values.
- Record significant client decisions in `docs/adr/`.

## Safety

- Never read or expose `.env*`, `*.tfvars`, secret or credential files, private keys, authentication files, or secret-bearing environment values.
- Use vault or CI identity references; never commit literal secrets.
- Read, validate, lint, and test may be automated. Confirm deploy, destroy, authentication changes, secret mutation, and shared-state destruction.
- Require an explicit `--profile <name>` for every Databricks command.

## Verification

- Run the repository's documented validation commands before completion. If none exist, inspect existing automation and report the gap instead of inventing a command.

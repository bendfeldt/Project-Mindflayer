# Project Instructions

<!-- template: AGENTS | version: 3.0.0 -->

## Repository identity

- **client:** {CLIENT_NAME}
- **platform:** {PLATFORM}
- **repository type:** {REPO_TYPE}
- **resource prefix:** `{prefix}`

## Project conventions

- Record client-specific naming, environments, regions, build commands, and architecture constraints here.
- Keep Dev, Test, and Prod structurally identical and configuration-driven.
- Put significant client decisions in `docs/adr/`.

## Safety

- Never read or expose `.env*`, `*.tfvars`, secret or credential files, private keys, authentication files, or secret-bearing environment values.
- Use vault or CI identity references; never commit literal secrets.
- Read, validate, lint, and test may be automated. Confirm deploy, destroy, authentication changes, secret mutation, and destructive operations.
- Require an explicit `--profile <name>` for every Databricks command.

## Branching and verification

- `main` is protected and production-bound unless this repository documents otherwise.
- Use short-lived feature branches and Conventional Commits.
- Run repository tests and validation before completion.

## Tool layout

Claude and Copilot may consume committed skills from `.claude/skills/`. Tool-specific instruction files are compatibility shims; this file remains authoritative.

# Repository Instructions

Project-Mindflayer distributes portable AI-assistant guidance, skills, settings, templates, and lifecycle tools.

## Invariants

- `AGENTS.md` is the sole substantive repository guidance; runtime-specific files are compatibility shims.
- `manifest.tsv` is the canonical distributable inventory and lifecycle-version registry.
- Existing user configuration is preserved unless replacement is explicitly authorized and backed up.
- Uninstall removes only artifacts whose toolkit ownership is recorded and verified.
- All ten public skill names remain stable.
- The repository itself is exempt from its generated project layout.

## Maintenance protocol

1. Start every non-lookup task with an approved `plan.md`.
2. Add or remove distributables through `manifest.tsv`; do not create secondary file manifests.
3. Keep skill frontmatter to `name` and `description`; put lifecycle versions in the manifest and metadata in `agents/openai.yaml`.
4. Put enduring rules in `global/AGENTS.md`, this file, or a normative reference. Use ADRs only for significant repository design decisions.
5. Preserve existing flags and the five supported consumers: Claude, Codex, Gemini, Cursor, and Copilot.
6. Never read prohibited secret files or values. See `docs/operating-standards.md`.
7. For Databricks examples, require an explicit `--profile <name>`; never select a profile automatically.
8. Before completion, run `bash tests/test-install.sh` and `python3 -m unittest discover -s tests -p 'test_*.py'`.

Do not reorganize the repository, deploy, publish, commit, or change external systems without explicit authorization.

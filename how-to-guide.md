# How-to Guide

## Global installation

Choose tools explicitly; names are validated and duplicates are rejected.

```bash
bash install.sh --global --tools claude,codex,copilot --local
```

Replacements are opt-in:

```bash
bash install.sh --global --tools claude,codex,copilot --force --local
```

Every replaced file receives a timestamped sibling backup. The version stamp changes only after complete success.

## Project installation

Run from the target client repository, never from Project-Mindflayer itself:

```bash
bash /path/to/install.sh --project --tools claude,copilot \
  --profile databricks --client "Client" --prefix cl --local
```

Profiles are `terraform`, `databricks`, and `fabric`. They select permission settings, not Databricks authentication. Every actual Databricks command still requires an explicitly user-selected `--profile <name>`.

Existing managed projects enter join mode: `AGENTS.md` is preserved while missing selected-tool artifacts are added. Project skills are real files under `.claude/skills/`.

## Lifecycle

```bash
~/.ai-toolkit/check-skills-update.sh
~/.ai-toolkit/sync-skills.sh --dry-run
~/.ai-toolkit/check-template-update.sh
~/.ai-toolkit/check-stores.sh --file ./stores.yml
~/.ai-toolkit/uninstall.sh --global
~/.ai-toolkit/uninstall.sh --global --confirm
```

Drift checks compare complete skill directories, including `agents/`, `references/`, and `scripts/`. Uninstall previews by default and preserves modified files unless forced removal is explicitly requested.

## Adding an artifact

1. Add the source file.
2. Add exactly one `manifest.tsv` row with type, lifecycle version, consumers, and ownership.
3. Add or update validation.
4. Run the complete test suite.

Do not add a second file list to lifecycle scripts or documentation.

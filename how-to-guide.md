# How-to Guide

## Global installation

Choose tools explicitly; names are validated and duplicates are rejected.

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --global --tools claude,codex,copilot
```

Canonical skills remain under `~/.ai-toolkit/skills/`. Verified links expose them to selected consumers: Codex under `~/.agents/skills/`, Claude under `~/.claude/skills/`, and Copilot under `~/.copilot/skills/`.

Replacements are opt-in:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --global --tools claude,codex,copilot --force
```

Every replaced path receives a timestamped sibling backup. The version stamp changes only after a complete installation succeeds.

## Project installation

Run in the target client repository, never from Project-Mindflayer itself:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --project --tools claude,codex \
  --project-types data-platform,data-engineering \
  --technologies databricks,databricks:asset-bundles,dbt,python,sql \
  --client "Client" --prefix cl
```

`--project-types` accepts one or more of `infrastructure`, `data-platform`, and `data-engineering`. All non-empty combinations are valid. `--technologies` accepts canonical identifiers from `config/technology-catalog.tsv`, including namespaced ecosystem components such as `databricks:unity-catalog`, `fabric:warehouse`, and `snowflake:snowpark`.

Project types are descriptive. Technologies compose guidance and Claude permissions. A namespaced component contributes its own policy but does not inherit its parent ecosystem's policy.

The legacy `--profile terraform|databricks|fabric` interface remains supported for existing automation and cannot be combined with the plural flags. It selects legacy project metadata and settings, not a Databricks authentication profile. Every Databricks command requires an explicitly user-selected `--profile <name>`. Snowflake commands requiring a connection must name it explicitly.

Existing managed projects enter join mode: `AGENTS.md` is preserved while missing selected-tool artifacts are added. Join mode reads plural metadata from new projects and falls back to the legacy `platform` field. Explicit flags must match stored metadata.

Project skills are complete real-file trees under `.agents/skills/` for Codex and `.claude/skills/` for Claude or Copilot. A mixed install writes shared trees once.

| Consumer | Project instruction entry point |
|---|---|
| Claude | `CLAUDE.md` imports `AGENTS.md` |
| Gemini | `GEMINI.md` imports `AGENTS.md` |
| Codex | Reads `AGENTS.md` directly |
| Cursor | Reads `AGENTS.md` directly |
| Copilot | Reads `AGENTS.md` directly |

Upgrades remove legacy Cursor and Copilot shims only when recorded ownership proof still matches. Modified or unowned files are preserved.

## Lifecycle

Run project drift and synchronization commands from the project root:

```bash
~/.ai-toolkit/check-skills-update.sh
~/.ai-toolkit/sync-skills.sh --dry-run
~/.ai-toolkit/check-template-update.sh
~/.ai-toolkit/check-stores.sh --file ./stores.yml
~/.ai-toolkit/uninstall.sh --global
~/.ai-toolkit/uninstall.sh --global --confirm
```

Drift checks compare complete skill directories, including `agents/`, `references/`, and `scripts/`. Synchronization derives roots exclusively from `.mindflayer-managed.tsv` and refuses conventionally named but unmanaged directories. Uninstall previews by default and preserves modified files unless forced removal is explicitly requested.

## Adding an artifact

1. Add the source file.
2. Add exactly one `manifest.tsv` row with type, lifecycle version, consumers, and ownership.
3. Add or update validation for every declared consumer.
4. Run the complete test suite.

Do not maintain a second artifact list in lifecycle scripts or documentation.

## Adding a technology

1. Add one canonical entry to `config/technology-catalog.tsv`; use a namespaced identifier for an ecosystem component.
2. Add only verified, non-mutating Claude command patterns to `settings/claude/technology-permissions.tsv`. Guidance-only entries need no policy rows.
3. Bump the catalog or policy lifecycle version in `manifest.tsv` when it changes.
4. Test aliases, canonical ordering, mixed composition, deny precedence, and vendor-specific profile or connection requirements.

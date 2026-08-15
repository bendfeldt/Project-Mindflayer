# How-to Guide

## Global installation

Choose tools explicitly; names are validated and duplicates are rejected.

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --global --tools claude,codex,copilot
```

The canonical skills remain under `~/.ai-toolkit/skills/`. A shared capability workflow creates verified links for selected consumers: Codex under `~/.agents/skills/`, Claude under `~/.claude/skills/`, and Copilot under `~/.copilot/skills/`.

Replacements are opt-in:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --global --tools claude,codex,copilot --force
```

Every replaced path receives a timestamped sibling backup. The version stamp changes only after the complete installation succeeds.

## Project installation

Run this in the target client repository, never from Project-Mindflayer itself:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --project --tools claude,codex \
  --profile databricks --client "Client" --prefix cl
```

The supported profiles are `terraform`, `databricks`, and `fabric`. They select permission settings, not Databricks authentication. Every actual Databricks command still requires an explicitly user-selected `--profile <name>`. Run project installation from the target repository; all installer artifacts are fetched from GitHub.

Existing managed projects enter join mode: `AGENTS.md` is preserved while missing selected-tool artifacts are added. Project skills are complete real-file trees under `.agents/skills/` for Codex and `.claude/skills/` for Claude or Copilot. A mixed install writes both trees once.

Project instruction discovery is consumer-native:

| Consumer | Project instruction entry point |
|---|---|
| Claude | `CLAUDE.md` imports `AGENTS.md` |
| Gemini | `GEMINI.md` imports `AGENTS.md` |
| Codex | Reads `AGENTS.md` directly |
| Cursor | Reads `AGENTS.md` directly |
| Copilot | Reads `AGENTS.md` directly |

Upgrades remove legacy Cursor and Copilot shims only when their recorded ownership proof still matches. Modified or unowned files are preserved.

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

Drift checks compare complete skill directories, including `agents/`, `references/`, and `scripts/`. Drift and synchronization derive their roots exclusively from `.mindflayer-managed.tsv`; they refuse conventionally named but unmanaged directories. Uninstall previews by default and preserves modified files unless forced removal is explicitly requested.

## Adding an artifact

1. Add the source file.
2. Add exactly one `manifest.tsv` row with its type, lifecycle version, consumers, and ownership.
3. Add or update validation for all declared consumers.
4. Run the complete test suite.

Do not maintain a second file list in lifecycle scripts or documentation.

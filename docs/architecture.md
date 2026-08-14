# Architecture

Project-Mindflayer has three layers:

1. A portable installed baseline containing universal working, safety, and architecture rules.
2. A thin repository `AGENTS.md` containing engagement-specific configuration.
3. Ten reusable skills containing operational workflows and nested resources.

`AGENTS.md` is the substantive repository contract. Claude, Codex, Gemini, Cursor, and Copilot compatibility files contain only routing notes.

## Distribution contract

`manifest.tsv` has five tab-separated fields:

| Field | Meaning |
|---|---|
| `path` | Repository-relative source path |
| `type` | Baseline, template, skill, resource, document, setting, shim, script, or registry |
| `version` | Artifact lifecycle version |
| `consumers` | Comma-separated installation scopes |
| `ownership` | Uninstall ownership class |

Global shared artifacts install under `~/.ai-toolkit/`. Claude and Copilot receive verified skill symlinks to that shared tree. Project installs copy full skill directories into `.claude/skills/` so cloud and cloned sessions receive nested resources.

The installer fetches the manifest first, then fetches exactly the selected rows. Local and remote modes therefore share one inventory. A successful global install writes the toolkit release stamp last.

## Ownership lifecycle

Existing files are preserved by default. Explicit `--force` replacement first creates a timestamped backup. Install records managed path, ownership class, content fingerprint, and symlink target. Drift and uninstall use this state rather than assuming that a familiar path is toolkit-owned.

The root distribution repository is deliberately exempt from project installation: generated client layout would duplicate its distribution sources and pollute its own governance.

## Versions

- Toolkit release: `VERSION` in `install.sh` and the completed-install stamp.
- Template schema: the `templates/AGENTS.md` header.
- Skill lifecycle: manifest rows for each skill tree.

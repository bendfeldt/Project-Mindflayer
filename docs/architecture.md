# Architecture

Project-Mindflayer has three layers:

1. A portable installed baseline with universal workflow and safety rules plus task routing.
2. A thin repository `AGENTS.md` for verified engagement-specific configuration and a standalone safety floor.
3. Ten reusable skills containing operational workflows and nested resources.

`AGENTS.md` is the substantive repository contract. Claude and Gemini import it through one-line native files; Codex, Cursor, and Copilot read it directly. Runtime discovery directories contain real scoped extensions, never compatibility shims or instructional scaffolding.

## Distribution contract

`manifest.tsv` has five tab-separated fields:

| Field | Meaning |
|---|---|
| `path` | Repository-relative source path |
| `type` | Artifact class, such as baseline, template, skill, resource, setting, or script |
| `version` | Artifact lifecycle version |
| `consumers` | Comma-separated installation scopes or capabilities |
| `ownership` | Uninstall ownership class |

Global shared artifacts install under `~/.ai-toolkit/`. Skill rows use the `global,project:skills` capability instead of repeating tool names. A single tool-and-scope mapping resolves the discovery roots for every selected skill-aware consumer.

Global skills remain canonical in `~/.ai-toolkit/skills/` and are linked into each selected discovery root. Project installs copy complete skill directories as real files: Codex uses `.agents/skills/`, while Claude and Copilot use `.claude/skills/`. The installer fetches each artifact once and deduplicates shared roots.

Public installation streams `install.sh` from `https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh`. The installer then fetches the manifest and exactly its selected rows from the same canonical GitHub repository. The local source mode is retained only for repository development and tests. A successful global install writes the toolkit release stamp last.

Obsolete project artifacts are removed during upgrade only when their recorded ownership proof still matches. Modified or unowned files are preserved.

## Ownership lifecycle

Existing paths are preserved by default. Explicit `--force` replacement first creates a timestamped backup. Installation records each managed path with its ownership class and either a content fingerprint or symlink target. Drift and synchronization derive project roots from that ledger and reject unsafe or unmanaged paths. Uninstall removes only artifacts whose recorded ownership proof still matches and prunes empty managed parent directories.

The root distribution repository is deliberately exempt from project installation: generated client `.claude/` and `.agents/` layouts would mix distribution sources with installed artifacts.

## Version domains

- `VERSION` in `install.sh`: toolkit release version.
- The header in `templates/AGENTS.md`: repository-template schema version.
- Skill and skill-resource rows in `manifest.tsv`: skill lifecycle version.

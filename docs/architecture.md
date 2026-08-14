# Architecture

Project-Mindflayer has three layers:

1. A portable installed baseline with universal working, safety, and architecture rules.
2. A thin repository `AGENTS.md` for engagement-specific configuration.
3. Ten reusable skills containing operational workflows and nested resources.

`AGENTS.md` is the substantive repository contract. Claude, Codex, Gemini, Cursor, and Copilot compatibility files contain only routing notes.

## Distribution contract

`manifest.tsv` has five tab-separated fields:

| Field | Meaning |
|---|---|
| `path` | Repository-relative source path |
| `type` | Artifact class, such as baseline, template, skill, resource, setting, or script |
| `version` | Artifact lifecycle version |
| `consumers` | Comma-separated installation scopes |
| `ownership` | Uninstall ownership class |

Global shared artifacts install under `~/.ai-toolkit/`. Skills remain canonical in `~/.ai-toolkit/skills/`; selected consumers receive verified per-skill symlinks in `~/.claude/skills/`, `~/.agents/skills/`, or `~/.copilot/skills/`.

Project installs copy complete skill directories as real files. Codex discovers them under `.agents/skills/`; Claude and Copilot use `.claude/skills/`. Mixed tool selections may therefore create both roots, while tools sharing a root are copied only once. Nested scripts, references, and metadata follow the owning skill.

The installer fetches the manifest first and then fetches exactly its selected rows. Local and remote modes therefore share one inventory. A successful global install writes the toolkit release stamp last.

## Ownership lifecycle

Existing paths are preserved by default. Explicit `--force` replacement first creates a timestamped backup. Installation records each managed path with its ownership class and either a content fingerprint or symlink target. Uninstall removes only artifacts whose recorded ownership proof still matches and prunes empty managed parent directories.

The root distribution repository is deliberately exempt from project installation: generated client `.claude/` and `.agents/` layouts would mix distribution sources with installed artifacts.

## Version domains

- `VERSION` in `install.sh`: toolkit release version.
- The header in `templates/AGENTS.md`: repository-template schema version.
- Skill and skill-resource rows in `manifest.tsv`: skill lifecycle version.

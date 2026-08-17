# Architecture

Project-Mindflayer has three layers:

1. A portable installed baseline with universal workflow and safety rules plus task routing.
2. A thin repository `AGENTS.md` with verified engagement-specific configuration and a standalone safety floor.
3. Eleven reusable skills containing operational workflows and nested resources.

`AGENTS.md` is the substantive repository contract. Claude and Gemini import it through one-line native files; Codex, Cursor, and Copilot read it directly. Runtime discovery directories contain real scoped extensions, never compatibility shims or instructional scaffolding.

## Runtime architecture

Linux and macOS use the Bash 3.2-compatible installer and lifecycle tools.
Windows 10/11 uses PowerShell 7.4+-compatible counterparts, with PowerShell 7.4
LTS as the baseline, and does not require a Unix compatibility layer. Native
Windows behavior is CI-tested on GitHub's Windows runner. Git Bash is unsupported
and WSL2 remains best effort. Installed artifacts are platform-scoped: Bash
installer and lifecycle scripts target Linux/macOS, while PowerShell counterparts
target Windows. Release-draft tooling installs its AppleScript helper only on
macOS and its portable Python 3.12+ `.eml` generator on Linux/Windows. Both
runtimes consume the same manifest, templates, technology catalog, policies, and
ownership model and must render project artifacts deterministically. Global
Windows skill discovery uses verified NTFS directory junctions; project skill
trees remain real files. Supported platforms and capability-specific dependencies
are defined in [system requirements](system-requirements.md).

## Project classification

New project installations model repository types and technologies as independent ordered sets. Repository types describe responsibilities and never grant permissions. Technologies are canonical identifiers from `config/technology-catalog.tsv`; ecosystem components use namespaced identifiers and contribute only their own policy.

Claude project settings are composed deterministically from the line-oriented technology policy. Exact duplicates are removed, identical denies suppress allows, and overlapping deny patterns remain. The installer performs composition with Bash 3.2-compatible shell and `awk` without adding a JSON-tool dependency.

The legacy single-profile path remains isolated: it uses the original template and static settings files. Join mode recognizes both schemas and never rewrites existing project guidance.

## Distribution contract

`manifest.tsv` has six tab-separated fields:

| Field | Meaning |
|---|---|
| `path` | Repository-relative source path |
| `type` | Artifact class such as baseline, template, skill, resource, setting, or script |
| `version` | Artifact lifecycle version |
| `consumers` | Comma-separated installation scopes or capabilities |
| `ownership` | Uninstall ownership class |
| `platforms` | Explicit comma-separated subset of `linux`, `macos`, and `windows` |

Global shared artifacts install under `~/.ai-toolkit/`. Skill rows use the `global,project:skills` capability instead of repeating tool names. A single tool-and-scope mapping resolves discovery roots for every selected skill-aware consumer.

Global skills remain canonical in `~/.ai-toolkit/skills/` and are linked into each selected discovery root. Project installs copy complete skill directories as real files: Codex uses `.agents/skills/`, while Claude and Copilot use `.claude/skills/`. The installer reads each bundled artifact once and deduplicates shared roots.

Public installation streams a release-hosted bootstrap entry point and requires
explicit mode and tool flags. The wrapper selects the platform, downloads the
versioned archive into temporary staging, and verifies its checksum and Cosign
keyless signature against the repository release workflow identity. Release
packaging projects one canonical manifest into platform-specific archives; no
second source inventory is maintained. Installers read the locally verified
archive and install only rows matching the target platform. The hidden local
flag remains an internal compatibility test path.

A successful global install writes the toolkit release stamp last. Obsolete project artifacts are removed during upgrade only when recorded ownership proof still matches. Modified or unowned files are preserved.

## Ownership lifecycle

Existing paths are preserved by default. Explicit `--force` replacement first creates a timestamped backup. Installation records each managed path and its content fingerprint or symlink target.

Drift synchronization derives project roots from the ownership ledger and rejects unsafe unmanaged paths. Uninstall removes only artifacts whose recorded ownership proof still matches and prunes empty managed parent directories.

The distribution repository is deliberately exempt from project installation because generated client `.claude/` and `.agents/` layouts would mix distribution sources with installed artifacts.

## Version domains

- `VERSION` in `bootstrap.sh` and `install.sh`: toolkit release version.
- Headers in `templates/AGENTS*.md`: repository-template schema versions.
- Skill and skill-resource rows in `manifest.tsv`: skill lifecycle versions.

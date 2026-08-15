# Project-Mindflayer

Portable configuration and operational skills for Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot.

## Install

Install globally from GitHub:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --global --tools claude,codex
```

Into a client repository:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --project \
  --tools claude,codex --profile terraform \
  --client "Client name" --prefix client
```

Run the project command from the target repository. The installer and installed copies fetch artifacts from the canonical GitHub repository. Existing files are skipped by default; `--force` explicitly authorizes replacement and creates timestamped backups.

Global skills live in the canonical `~/.ai-toolkit/skills/` store. One capability-driven workflow exposes them through the discovery roots of every selected skill-aware tool. Project installs commit each complete skill tree once per distinct discovery root.

## Contents

- Ten public skills, including their nested scripts and references.
- One portable global baseline and one thin project template.
- Native project discovery: Claude and Gemini import `AGENTS.md`; Codex, Cursor, and Copilot read it directly.
- Manifest-driven install, drift, sync, update, store, and uninstall tooling.

`manifest.tsv` is the canonical artifact inventory. Its version column tracks artifact lifecycle versions. `VERSION` in `install.sh` is the toolkit release, while the header in `templates/AGENTS.md` is the template schema version.

See [architecture](docs/architecture.md), [operating standards](docs/operating-standards.md), and the [how-to guide](how-to-guide.md).

## Safety

The installer never silently replaces existing agent configuration. Drift, synchronization, and uninstall operate only on paths recorded as toolkit-owned. Uninstall is dry-run by default, and the toolkit repository deliberately does not install its own generated `.claude/` or `.agents/` client layout.

## Validate

The Bash test suite requires ShellCheck `0.11.0`, matching the pinned CI version.

```bash
bash tests/test-install.sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

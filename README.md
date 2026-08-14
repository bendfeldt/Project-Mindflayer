# Project-Mindflayer

Portable configuration and operational skills for Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot.

## Install

From a checkout:

```bash
bash install.sh --global --tools claude,codex --local
```

Into a client repository:

```bash
bash /path/to/Project-Mindflayer/install.sh --project \
  --tools claude,codex --profile terraform \
  --client "Client name" --prefix client --local
```

Remote installation uses the same flags without `--local`. Existing files are skipped by default. `--force` explicitly authorizes replacement and creates timestamped backups.

## Contents

- 10 public skills, including nested scripts and references.
- One portable global baseline and one thin project template.
- Consumer-specific settings and compatibility shims.
- Manifest-driven install, drift, sync, update, store, and uninstall tooling.

`manifest.tsv` is the canonical artifact inventory. Its version column tracks artifact lifecycle versions. `VERSION` in `install.sh` is the toolkit release. The header in `templates/AGENTS.md` is the template schema version.

See [architecture](docs/architecture.md), [operating standards](docs/operating-standards.md), and the [how-to guide](how-to-guide.md).

## Safety

The installer never silently replaces existing agent configuration. Uninstall is dry-run by default and removes only verified toolkit-owned artifacts. The toolkit repository does not install its own generated `.claude/` client layout.

## Validate

```bash
bash tests/test-install.sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

---
name: setup-repo
description: Configure a client repository with Project-Mindflayer by collecting project types, technologies, client identity, optional resource prefix, and selected assistant tools.
---

# Set Up Repository

Delegate installation behavior to the toolkit `install.sh`; do not recreate it.

1. Confirm the target is not the Project-Mindflayer distribution repository.
2. Detect available assistants and ask for the explicit tool list to configure.
3. For a new project, collect:
   - One or more project types: `infrastructure`, `data-platform`, `data-engineering`.
   - Technologies from the installed `~/.ai-toolkit/config/technology-catalog.tsv`. If it is unavailable, read the canonical repository copy; never invent an identifier. Use namespaced identifiers for platform components.
   - Client name.
   - Resource prefix only when the repository uses one.
4. Preview and obtain approval for:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --project \
  --tools <comma-separated-tools> \
  --project-types <comma-separated-project-types> \
  --technologies <comma-separated-technologies> \
  --client "<client>" [--prefix <prefix>]
```

5. Run it in the target repository and report only tool-conditional artifacts actually created.
6. Validate project instruction discovery:
   - Claude: `CLAUDE.md` is exactly `@AGENTS.md`.
   - Gemini: `GEMINI.md` is exactly `@AGENTS.md`.
   - Codex, Cursor, Copilot: use root `AGENTS.md` directly with no compatibility shim.
7. Validate selected settings and complete skill trees.

Project types are descriptive and may be combined freely. Technologies compose guidance and Claude permissions. A namespaced component identifies its ecosystem but does not inherit the parent ecosystem's permissions.

Existing automation may continue using `--profile terraform|databricks|fabric`; never combine that legacy interface with the plural flags. A Databricks technology or legacy profile never selects authentication. Never invent or auto-select a Databricks CLI profile, and require `--profile <name>` on every Databricks command.

Join mode preserves `AGENTS.md`. If explicit classification flags are supplied, they must match stored metadata.

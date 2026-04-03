# GitHub Copilot Instructions

See AGENTS.md in the repo root for all project conventions, safety rules,
and platform-specific instructions.

This file exists because GitHub Copilot reads from .github/copilot-instructions.md.
If your repo has an AGENTS.md (which Copilot also reads), you can replace this file
with a symlink:

    ln -sf ../AGENTS.md .github/copilot-instructions.md

## Copilot-Specific Notes

- Copilot does not have permission settings like Claude Code or Codex
- All safety rules are expressed in AGENTS.md and enforced via instructions
- For code review via Copilot, follow the ADR and compliance conventions in AGENTS.md

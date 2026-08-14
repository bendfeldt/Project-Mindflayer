---
name: release-notes
description: Collect evidence and prepare provider-aware release notes without publishing or overwriting remote descriptions by default.
---

# Release Notes

Resolve all scripts relative to this skill directory, never the current working directory.

1. Read [provider behavior](references/providers.md) and [templates](references/templates.md).
2. Resolve configuration precedence: explicit CLI values, repository config, then documented defaults. Reject ambiguous project or work-item mappings.
3. Run `scripts/collect_evidence.py` and `scripts/merge_release.py` using absolute paths derived from the skill directory.
4. Preview merged notes and provider commands.
5. Default to dry-run and refuse overwrite unless explicitly authorized.
6. Ask before any remote write or Outlook draft creation.
7. Report evidence gaps, conflicts, and generated local artifacts.

Use installed helpers from `~/.ai-toolkit/skills/release-notes/scripts/` for global installs or `.claude/skills/release-notes/scripts/` for project installs.

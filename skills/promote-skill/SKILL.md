---
name: promote-skill
description: >
  Promote a skill from a client repo's ./.claude/skills/ up to the
  Project-Mindflayer toolkit so it becomes a global capability. Use when the user
  says "promote this skill", "elevate this skill to toolkit", "this should be a
  global skill", "/promote-skill", or asks to make a client skill reusable across
  engagements.
version: 1.0.0
updated: 2026-04-23
---

# Promote Skill

Lift a `SKILL.md` (and any supporting files) from the current client repo's
`./.claude/skills/<name>/` into the Project-Mindflayer toolkit's `skills/`
directory so it is distributed to all future engagements. Generalize
client-specific language, bump the version, and offer to replace the source
with a pointer to the canonical location.

## When to promote

A skill is a candidate for promotion when **all** of these are true:

- The skill would apply to ≥ 2 future client engagements without modification
- The skill is not tied to a single client's compliance, vendor, or org setup
- The playbook can be generalized without losing meaning

If any of these fail, keep the skill local to the client repo.

## When to NOT promote (keep local)

- Skills that hard-code a specific client's repo layout, subscription, or
  tenant IDs
- Skills that embed client-proprietary procedures
- Skills that reference secrets, credentials, or customer PII — even
  indirectly

## Process

Follow these steps every time:

1. **Locate the source skill**
   - Ask the user which skill to promote if not specified
   - Default location: `./.claude/skills/<name>/`
   - Read `SKILL.md` and list any supporting files in the skill directory
   - Confirm with the user before proceeding

2. **Locate the toolkit target**
   - Default: `$HOME/repos/Bendfeldt/Project-Mindflayer/skills/`
   - Accept override via user-specified path
   - Verify the directory exists and is a git working tree

3. **Collision check**
   - If `$TOOLKIT/skills/<name>/` already exists, compare versions:
     - Local version > toolkit version → treat as an **update**
     - Local version == toolkit version with content diff → bump the version
       (patch for fixes, minor for additions, major for breaking changes) and
       treat as an **update**
     - Local version < toolkit version → stop; the toolkit is already ahead.
       Suggest rebasing the client skill on the toolkit version first.
   - If no collision → treat as a **new skill**

4. **Portability review**
   - Scan the source skill for client-specific markers:
     - Client or organization names
     - Specific project, repo, or system names
     - Hard-coded paths that reference a specific engagement
     - Compliance items that apply only to one jurisdiction or client
     - Named individuals other than the skill author
   - Present each finding with a proposed redaction or generalization
   - **If the skill cannot be generalized without losing its meaning, stop**
     and recommend keeping it client-local

5. **Rewrite the skill for global context**
   - Keep the `name:` field the same (skill identity is stable)
   - Update `version:` per the collision-check decision (or set to `1.0.0` for new)
   - Update `updated:` to today's date
   - Replace client-specific language with generalized equivalents:
     - "the client" → "a consultant engagement"
     - specific tools → "the client's standard toolchain"
     - specific platforms → the generic category
   - Append a **Promoted from** footer at the bottom of `SKILL.md`:
     ```
     ---
     **Promoted from:** `<source-repo>/.claude/skills/<name>/` (commit `<short-sha>`)
     ```

6. **Include supporting files**
   - Copy any `references/`, `scripts/`, `examples/`, or other files from the
     source skill directory
   - Apply the same portability review to supporting files
   - Preserve relative paths inside the skill directory

7. **Show the diff before writing**
   - Display the rewritten `SKILL.md` in full
   - List all supporting files being copied
   - Highlight every change made vs. the source
   - Wait for explicit user approval

8. **Write the promoted skill**
   - Save to `$TOOLKIT/skills/<name>/SKILL.md` plus all supporting files
   - Do **not** run `git add` or `git commit` in the toolkit repo — hand off to
     `/smart-commit` in that repo
   - **Remind the user** to update `SKILL_FILES` in `$TOOLKIT/install.sh` if
     the skill is new, and the skill list in
     `$TOOLKIT/templates/AGENTS.md` if it adds a notable capability

9. **Offer to replace the source**
   - Ask: "Replace the source skill with a pointer to the canonical toolkit skill?"
   - If yes, replace the source `SKILL.md` with a thin stub that redirects to
     `~/.ai-toolkit/skills/<name>/` and documents that updates come via
     `install.sh --project` refresh
   - Do not auto-commit in the client repo either

10. **Summary**
    - Show the target path written
    - List client-repo follow-ups (commit in client, commit in toolkit, push both,
      update `install.sh` manifest if new)
    - Do not perform these steps unless the user explicitly asks

## Safety rules

- **Never auto-commit** in either repo
- **Never promote a skill that references secrets, credentials, or customer PII** —
  stop and ask the user to rewrite first
- **Never overwrite a toolkit skill without bumping its version**
- **Never delete the source skill** without replacing it with a pointer stub
- If the toolkit repo is not at the default path, ask the user to confirm the
  path before writing
- Preserve the YAML frontmatter format (Agent Skills open standard) — do not
  convert to HTML-comment headers

## Relationship to `/promote-adr`

`/promote-skill` is the symmetric counterpart of `/promote-adr`. The two skills
share the same philosophy: decisions and capabilities authored in a client
engagement that prove broadly useful get elevated to the toolkit so future
engagements inherit them automatically.

## Example

Source skill at `./.claude/skills/fabric-semantic-model/SKILL.md` in a
client repo, containing a playbook for designing Fabric semantic models. After
review it applies broadly to any Fabric engagement. Promote to
`$TOOLKIT/skills/fabric-semantic-model/SKILL.md`, generalize "the ACME dataset"
to "the target semantic model", bump version to `1.0.0`, replace the client
file with a pointer, and hand off commits to `/smart-commit` in each repo. Then
update `SKILL_FILES` in `install.sh` to include the new skill.

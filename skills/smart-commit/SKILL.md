---
name: smart-commit
description: >
  Review staged and unstaged changes, generate a clear business-friendly commit
  message, stage the files, and commit. Use when the user says "commit my changes",
  "/commit", "create a commit", "save my work", or "commit and push". Also trigger
  when the user asks for help writing a commit message for the current changes.
---

# Smart Commit

Inspect the current changes, understand what they mean for the project, write a
commit message that explains *what changed and why* in terms a business user or
future consultant can understand — not just the file names or technical mechanics.

## Process

Follow these steps every time:

1. **Inspect the working tree**
   - Run `git status` — see staged, unstaged, and untracked files
   - Run `git diff --staged` — review already-staged changes in full
   - Run `git diff` — review unstaged changes that could be included
   - Run `git log --oneline -5` — understand the recent commit history and style

2. **Understand the story**
   - Group changes by theme: what problem does this set of changes solve?
   - Identify the dominant type: new capability, fix, cleanup, documentation, config
   - Determine the scope: which part of the project does this touch?

3. **Draft the commit message**
   - Follow the format and standard below
   - Write the description in plain business language
   - Add a body if the change needs more context

4. **Present for confirmation**
   - Show the full commit message (subject + body if present) before doing anything
   - Show which files will be staged
   - Wait for explicit approval — do not commit without it

5. **Stage and commit**
   - Stage specific files by name — never `git add -A` or `git add .` blindly
   - Never stage: `.env*`, `*.tfvars`, `*secret*`, `*.key`, `*.pem`, `*.pfx`
   - Commit using the approved message

6. **Offer to push**
   - Ask: "Push to origin/[branch]?" — never auto-push
   - Only push if the user explicitly confirms

---

## Commit Message Standard

**Format:** `type(scope): description`

### Type

| Type | Use when |
|---|---|
| `feat` | New capability, feature, or content added |
| `fix` | A bug, error, or incorrect behavior corrected |
| `docs` | Documentation, ADRs, comments — no logic changes |
| `refactor` | Code reorganized without changing observable behavior |
| `chore` | Maintenance: dependencies, configs, installer updates |
| `ci` | CI/CD pipeline, test suite, or automation changes |
| `security` | Security hardening or vulnerability fix |

### Scope (optional)

The area or module affected — use when it adds clarity:

| Scope | Use for |
|---|---|
| `toolkit` | Project-Mindflayer installer, global config |
| `kimball` | Kimball modeling skill or reference |
| `adr` | ADR skill or decision log |
| `stores` | External stores registry and check script |
| `installer` | `install.sh` logic, manifests, flag handling |
| `security` | Security fixes across scripts |
| `{platform}` | Databricks, fabric, sqlserver, terraform templates |

Omit scope if the change is cross-cutting or the type makes it clear.

### Description

Write for a business analyst or future consultant reading the git log:

- **Imperative mood:** "add", "remove", "fix", "update" — not "added", "adding"
- **Plain language:** describe the *business intent*, not the file changed
- **Max 72 characters**
- No trailing period

### Body (optional)

Add a blank line after the subject, then explain:
- *Why* the change was made — the business or technical motivation
- What problem it solves or what risk it addresses
- Any notable trade-offs or follow-up items

---

## Good vs. Bad Examples

| Bad (describes the file) | Good (describes the intent) |
|---|---|
| `feat: update SKILL.md with surrogate key content` | `feat(kimball): add client-validated DDL patterns for Databricks` |
| `fix: change curl header to use --config -` | `security: prevent API token from appearing in process listings` |
| `chore: update multiple files for platform changes` | `chore(stack): align platform profile to active Databricks/Fabric/SQL Server stack` |
| `feat: add DECISION_FILES array to install.sh` | `feat(toolkit): install decision log as part of global setup` |
| `chore: add stores.yml and check-stores.sh` | `feat(stores): add external store tracking with manual update model` |

The test: could a business stakeholder read the git log and understand what the project
is doing and why, without reading the diffs?

---

## Multi-Change Commits

When multiple unrelated changes are staged:
- Split into separate commits if the themes are clearly distinct
- Group if they belong to the same logical unit of work
- Ask the user if unclear: "These look like two separate changes — should I split them?"

---

## Safety Checks Before Every Commit

Before staging any file, verify:
- No `.env`, `.env.*`, `*.tfvars`, `*secret*`, `*.key`, `*.pem`, `*.pfx` files
- No hard-coded tokens, passwords, or connection strings in the diff
- No unintentional debug output or temporary test code
- If AGENTS.md was modified — confirm it's intentional (not an accidental client-specific change)

If a sensitive file is staged, stop immediately and warn the user.

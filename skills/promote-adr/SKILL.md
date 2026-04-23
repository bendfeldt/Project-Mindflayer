---
name: promote-adr
description: >
  Promote an ADR from a client repo up to the Project-Mindflayer toolkit so it
  becomes a global standard. Use when the user says "promote this ADR",
  "elevate this decision to toolkit", "this should be a global ADR",
  "/promote-adr", or asks to make a client decision reusable across engagements.
version: 1.0.0
updated: 2026-04-23
---

# Promote ADR

Lift an Architecture Decision Record from the current (client) repo into the
Project-Mindflayer toolkit's `docs/decisions/` directory so it is distributed to
all future engagements. Generalize client-specific language, assign a new toolkit
ADR number, and offer to replace the source with a pointer to the canonical
location.

## When to promote

An ADR is a candidate for promotion when **all** of these are true:

- The decision would apply to ≥ 2 future client engagements without modification
- The rationale is not tied to a single client's compliance, vendor, or org setup
- The content can be generalized without losing meaning

If any of these fail, keep the ADR local to the client repo.

## Process

Follow these steps every time:

1. **Locate the source ADR**
   - Ask the user which ADR to promote if not specified
   - Auto-detect common locations: `docs/decisions/`, `docs/adr/`, `adr/`
   - Read the full ADR file and confirm with the user before proceeding

2. **Locate the toolkit target**
   - Default: `$HOME/repos/Bendfeldt/Project-Mindflayer/docs/decisions/`
   - Accept override via user-specified path
   - Verify the directory exists and is a git working tree

3. **Portability review**
   - Scan the source ADR for client-specific markers:
     - Client or organization names
     - Specific project, repo, or system names
     - Hard-coded paths that reference a specific engagement
     - Compliance items that apply only to one jurisdiction or client
     - Named individuals other than the deciders
   - Present each finding with a proposed redaction or generalization
   - **If the ADR cannot be generalized without losing its meaning, stop** and
     recommend keeping it client-local

4. **Compute the next toolkit ADR number**
   - List files matching `NNNN-*.md` in the target directory
   - Next number = max(existing) + 1, zero-padded to four digits
   - Never reuse a number, even if a prior ADR was deleted

5. **Rewrite the ADR for global context**
   - Renumber the heading: `# ADR-00NN: <title>`
   - Update the `Deciders` field to "Michael Bendfeldt" (or the toolkit owner)
   - Update `Date` to today's date
   - Replace client-specific language with generalized equivalents:
     - "the client" → "a consultant engagement"
     - specific tools → "the client's standard toolchain"
     - specific platforms → the generic category (e.g., "Azure" stays, but
       "our Azure tenant" becomes "the target Azure tenant")
   - Append a **Promoted from** footer:
     ```
     ---
     **Promoted from:** `<source-repo>/<source-path>` (commit `<short-sha>`)
     ```

6. **Show the diff before writing**
   - Display the rewritten ADR in full
   - Highlight every change made vs. the source
   - Wait for explicit user approval

7. **Write the promoted ADR**
   - Save to `$TOOLKIT/docs/decisions/00NN-<kebab-slug>.md`
   - Do **not** run `git add` or `git commit` in the toolkit repo — hand off to
     `/smart-commit` in that repo

8. **Offer to replace the source**
   - Ask: "Replace the source ADR with a pointer to the canonical toolkit ADR?"
   - If yes, replace the source file contents with:
     ```
     # <original-title>

     **Superseded by toolkit ADR-00NN** — see
     `~/.ai-toolkit/docs/decisions/00NN-<slug>.md` or the Project-Mindflayer
     repo for the canonical decision.
     ```
   - Do not auto-commit in the client repo either

9. **Summary**
   - Show the target path written
   - List client-repo follow-ups (commit in client, commit in toolkit, push both)
   - Do not perform these steps unless the user explicitly asks

## Safety rules

- **Never auto-commit** in either repo
- **Never promote an ADR that references secrets, credentials, or customer PII**
  — stop and ask the user to rewrite first
- **Never overwrite an existing toolkit ADR** — always assign a new number
- **Never delete the source ADR** without replacing it with a pointer stub
- If the toolkit repo is not at the default path, ask the user to confirm the
  path before writing

## What NOT to promote

- Client-specific naming conventions (those belong in per-repo AGENTS.md)
- Compliance decisions tied to one client's regulatory scope
- Temporary workarounds or time-boxed experiments
- Build/deploy commands specific to one project

## Example

Source ADR at `./docs/adr/0003-use-medallion-for-silver-gold.md` in a client
repo, discussing why the engagement standardizes on bronze/silver/gold layers
for a Databricks lakehouse. After review it applies broadly to every data
engagement. Promote to
`$TOOLKIT/docs/decisions/0011-medallion-architecture-default.md`, generalize
"our KOMBIT lakehouse" to "the target lakehouse", replace the client-repo file
with a pointer, and hand off commits to `/smart-commit` in each repo.

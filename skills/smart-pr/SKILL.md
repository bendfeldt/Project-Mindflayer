---
name: smart-pr
description: >
  Review all changes in the current branch, generate a business-friendly pull request
  title and description, create the PR, and set it to auto-complete. Use when the user
  says "create a PR", "open a pull request", "/pr", "raise a PR", or "submit this branch
  for review". Works for both GitHub and Azure DevOps repos.
version: 1.0.0
updated: 2026-04-23
---

# Smart Pull Request

Inspect every commit and file change in the current branch, understand the business
value being delivered, write a clear PR title and description that a non-technical
stakeholder can understand, create the PR, and immediately set auto-complete so it
merges automatically once all policies pass.

## Process

Follow these steps every time:

1. **Identify the base branch**
   - Check `git remote show origin` or `git symbolic-ref refs/remotes/origin/HEAD` for the default branch
   - Fall back to `main` if neither resolves

2. **Review all branch changes**
   - Run `git log {base}..HEAD --oneline` — see every commit on this branch
   - Run `git diff --stat {base}...HEAD` — see every file changed and the scale of changes
   - Run `git diff {base}...HEAD` — read the actual changes to understand context

3. **Understand the story**
   - What theme connects all the commits? New capability, a fix, cleanup, documentation?
   - What business problem or request does this branch address?
   - Group the changes into 3-5 bullets that describe *what changed*, not *which files*

4. **Draft the PR title and body**
   - Write in the format and structure below
   - Apply the same plain-language principles as the smart-commit skill

5. **Present for confirmation**
   - Show the full PR title and body before creating anything
   - Show which platform was detected (GitHub or Azure DevOps)
   - Wait for explicit approval — never create a PR without it

6. **Create the PR**
   - GitHub: `gh pr create --title "..." --body "..." --base {base}`
   - Azure DevOps: `az repos pr create --title "..." --description "..." --target-branch {base}`

7. **Set auto-complete immediately after creation**
   - GitHub: `gh pr merge --auto --merge {PR_NUMBER}`
   - Azure DevOps: `az repos pr update --id {PR_ID} --auto-complete true`
   - **This step is mandatory** — always set auto-complete, never skip it

8. **Return the PR URL**

---

## PR Title Format

Same type vocabulary as smart-commit, written as a subject line:

`type(scope): description of what this PR delivers`

- **Imperative mood:** "add", "fix", "remove", "update"
- **Plain language:** describe the business capability, not the technical mechanics
- **Max 72 characters**

---

## PR Body Structure

```markdown
## What this PR does

[2-3 sentences in business language. What capability, fix, or improvement does this
deliver? What is the user or team now able to do that they couldn't before?]

## Changes included

- [Theme 1 — group related file changes into one bullet]
- [Theme 2]
- [Theme 3]
[3-6 bullets max. Group by purpose, not by file.]

## Why

[1-2 sentences on motivation. What request, problem, or observation prompted this work?]
```

---

## Platform Detection

Detect from the remote URL:

```bash
git remote get-url origin
```

| URL contains | Platform | PR tool |
|---|---|---|
| `github.com` | GitHub | `gh pr create` |
| `dev.azure.com` or `visualstudio.com` | Azure DevOps | `az repos pr create` |

If neither matches: warn the user and use `gh pr create` as fallback.

---

## Auto-Complete

Auto-complete merges the PR automatically once all branch policies are satisfied
(required reviewers approved, build passes, work items linked, etc.). It is always
set — this avoids PRs sitting open after approval.

- **GitHub:** `gh pr merge --auto --merge {PR_NUMBER}`
- **Azure DevOps:** `az repos pr update --id {PR_ID} --auto-complete true`

If auto-complete fails (e.g., permissions not granted), report it clearly and provide
the manual command the user can run.

---

## Good vs. Bad Examples

| Bad (describes files) | Good (describes value) |
|---|---|
| `feat: update SKILL.md, install.sh, and tests` | `feat(toolkit): add decision log to global install` |
| `chore: multiple file updates` | `chore(stack): align profile to Databricks/Fabric/SQL Server` |
| `fix: curl changes in check-stores.sh` | `security: prevent API token from leaking in process listings` |
| `feat: new stores.yml and check-stores.sh` | `feat(stores): track external community repos for updates` |

---

## Safety Checks Before Creating

- Confirm the branch has been pushed to origin: `git status` should show "Your branch is up to date" or "ahead of"
- If unpushed commits exist: offer to push first (`git push -u origin {branch}`)
- Never create a PR from `main` to `main`
- If the branch only has 1 commit, the PR body can be shorter — let the commit message carry the weight

---
name: smart-pr
description: >
  Review all changes in the current branch, generate a business-friendly pull request
  title and description, create the PR, and set it to auto-complete. Use when the user
  says "create a PR", "open a pull request", "/pr", "raise a PR", or "submit this branch
  for review". Works for both GitHub and Azure DevOps repos.
version: 1.1.0
updated: 2026-04-23
---

# Smart Pull Request

Inspect every commit and file change in the current branch, understand the business
value being delivered, write a clear PR title and description that a non-technical
stakeholder can understand, create the PR, link any work items attached to the branch,
and immediately set auto-complete (with delete-source-branch) so it merges automatically
once all policies pass.

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

4. **Detect branch work items**
   - Identify work items linked to the branch using the rules in
     [Work Item Linking](#work-item-linking) below
   - Keep the list handy for step 8 and for the PR body
   - If detection fails (API error, unauthenticated, platform not matched),
     warn but continue — never block the PR

5. **Draft the PR title and body**
   - Write in the format and structure below
   - Apply the same plain-language principles as the smart-commit skill
   - For GitHub: append `Fixes #N` lines for each detected issue (see PR Body
     Structure) so the issue auto-closes on merge

6. **Present for confirmation**
   - Show the full PR title and body before creating anything
   - Show which platform was detected (GitHub or Azure DevOps)
   - Show the detected work items (or "none detected")
   - Wait for explicit approval — never create a PR without it

7. **Create the PR**
   - GitHub: `gh pr create --title "..." --body "..." --base {base}`
   - Azure DevOps: `az repos pr create --title "..." --description "..." --target-branch {base}`

8. **Link work items to the PR**
   - Azure DevOps: list already-linked work items with
     `az repos pr work-item list --id {PR_ID}`; diff against detected IDs and
     attach missing ones with `az repos pr work-item add --id {PR_ID} --work-items <id1> <id2>`
   - GitHub: verify the `Fixes #N` lines in the PR body resolved to real
     issue links. If any didn't, warn the user.
   - Print a compact summary (see [Work Item Linking](#work-item-linking))
   - If anything fails (permissions, bad ID): warn with a copy-pastable manual
     command and continue — never block auto-complete on this

9. **Set auto-complete and delete-source-branch immediately after creation**
   - GitHub: `gh pr merge --auto --merge --delete-branch {PR_NUMBER}`
   - Azure DevOps: `az repos pr update --id {PR_ID} --auto-complete true --delete-source-branch true`
   - **This step is mandatory** — always set auto-complete *and* delete-source-branch,
     never skip them

10. **Return the PR URL**

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

Fixes #123
Fixes #456
```

On **GitHub**, append one `Fixes #N` line per detected issue (from step 4) so the
issues are linked to the PR and auto-close on merge. On **Azure DevOps**, omit the
`Fixes #N` block — work items are attached via the API in step 8 instead.

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

## Work Item Linking

Every work item linked to the branch must also be linked to the PR. This keeps
the delivery board in sync with what actually ships.

### Detection

- **Azure DevOps** — use the native Boards branch→work-item link. Query via
  `az devops invoke` against the work-item artifact-link API, filtering on the
  branch's artifact URI
  (`vstfs:///Git/Ref/{project}/{repo}/GB{branch}`). Example:

  ```bash
  az devops invoke \
      --area wit --resource artifactUriQuery \
      --route-parameters project="$PROJECT" \
      --http-method POST --api-version 7.1-preview \
      --in-file query.json
  ```

  where `query.json` contains the branch artifact URI. Collect the returned
  work item IDs.

- **GitHub** — parse the current branch name for issue references. Accept
  `#123`, `GH-123`, `issue-123`, or a bare leading/trailing number surrounded
  by `-`, `_`, or `/`. Example regex: `(?:^|[-_/])(?:#|GH-|issue-)?(\d+)(?:$|[-_/])`.
  Do **not** scan commit messages — branch name only keeps detection
  predictable and avoids noise from stale references.

If the platform isn't recognised, or detection fails, warn and continue with
zero detected IDs.

### Linking to the PR

- **Azure DevOps** — after PR creation:

  ```bash
  az repos pr work-item list --id "$PR_ID" --query "[].id" -o tsv   # already linked
  az repos pr work-item add  --id "$PR_ID" --work-items <missing ids>
  ```

- **GitHub** — append `Fixes #N` to the PR body for each detected issue (done
  as part of step 5). After creation, confirm the PR's linked issues include
  each detected ID; if any are missing, warn.

### Summary output

After step 8, print one of:

```
Work items: detected 3 on branch, 3 linked to PR ✓
```

or, on mismatch:

```
Work items: detected 3 on branch, 2 linked to PR
  ! Could not link: #457 (permission denied)
  Run manually: az repos pr work-item add --id <PR> --work-items 457
```

Mismatches never block the PR — they surface as warnings with a manual fix path.

---

## Auto-Complete

Auto-complete merges the PR automatically once all branch policies are satisfied
(required reviewers approved, build passes, work items linked, etc.). It is always
set — this avoids PRs sitting open after approval. The source branch is always
deleted on completion so branches don't accumulate after merge.

- **GitHub:** `gh pr merge --auto --merge --delete-branch {PR_NUMBER}`
- **Azure DevOps:** `az repos pr update --id {PR_ID} --auto-complete true --delete-source-branch true`

If either flag fails (e.g., permissions not granted, branch policy blocks
delete-on-complete), report it clearly and provide the manual command the user
can run.

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
- Work-item mismatches (detected on branch but not linked to PR) produce a warning with a manual fix command — **never block PR creation or auto-complete on a mismatch**

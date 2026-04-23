---
name: branch-cleanup
description: >
  Prune remote tracking branches and delete local branches whose upstream has
  been deleted on origin, including squash and rebase merges. Use when the
  user says "clean branches", "prune branches", "/prune", "delete stale
  branches", or "clean up old branches". Also triggered automatically after
  a push via smart-commit.
version: 1.1.0
updated: 2026-04-23
---

# Branch Cleanup

Fetch the latest remote state, identify **local** branches whose upstream
tracking branch has been deleted from origin, and remove them. This only
deletes local branches — it never modifies anything on the remote.

A branch's upstream showing `[gone]` is treated as consent to delete: the
remote (via PR auto-complete, admin cleanup, or an explicit delete) has
already decided the branch is done. The skill proceeds without per-branch
confirmation.

For squash-merged and rebase-merged branches — where `git branch -d` refuses
because SHAs differ even though the patch landed on main — the skill
performs a safe patch-identity check (see [Squash-merge detection]
(#squash-merge-detection)) and escalates to `git branch -D` only when the
work is provably already in the base branch.

## Process

Follow these steps every time:

1. **Fetch and prune remote tracking branches**
   - Run `git fetch --all --prune` — updates refs from all remotes, removes
     tracking branches for deleted remote branches
   - Run `git branch -vv` — show all local branches with their tracking status

2. **Identify stale branches**
   - Parse `git branch -vv` output for branches showing `: gone]` — these had
     upstream branches that no longer exist
   - Example: `git branch -vv | grep ': gone]' | awk '{print $1}'`
   - Exclude protected branches: never touch `main`, `master`, `develop`,
     `development`, `release/*`, `releases/*`, or the currently checked-out
     branch
   - Get current branch: `git rev-parse --abbrev-ref HEAD`

3. **Show what would be deleted**
   - If no stale branches found, report "No stale branches — nothing to
     clean up" and stop
   - Otherwise list each stale branch with its last commit:
     ```
     Stale branches (upstream deleted from origin):
       feature/old-thing   (last commit: abc1234 — 3 days ago)
       bug/mbe/17388       (last commit: def5678 — 1 day ago)
       orphan/draft        (last commit: 9999999 — 2 hours ago)
     ```
   - Show the total count

4. **Proceed without asking**
   - Do **not** prompt "Delete these N branches?" — the `[gone]` flag means
     the remote has already deleted the branch. That is consent.
   - Go straight to step 5 and delete each candidate according to the
     cascade rules.

5. **Delete each stale branch via the cascade**
   For each candidate branch (`$branch`):

   1. Try `git branch -d "$branch"`. On success, report `✓ Deleted $branch`.
   2. On failure (git reports "not fully merged"), run the
      [squash-merge detection](#squash-merge-detection).
      - If it reports squash-merged, run `git branch -D "$branch"` and
        report `✓ Deleted $branch (squash-merged)`.
      - If it does not, **keep** the branch and report
        `! Kept $branch — work is not on origin/{base}, review before deleting manually`.
        Do not force-delete: the remote branch was deleted but the work
        never landed, so this might be data loss (accidental remote delete).

6. **Summary**
   - Report e.g. `Cleaned up 2 stale branch(es). 1 kept for review.`

Example run:

```
Stale branches (upstream deleted from origin):
  feature/old-thing   (last commit: abc1234 — 3 days ago)
  bug/mbe/17388       (last commit: def5678 — 1 day ago)
  orphan/draft        (last commit: 9999999 — 2 hours ago)

✓ Deleted feature/old-thing
✓ Deleted bug/mbe/17388 (squash-merged)
! Kept orphan/draft — work is not on origin/main, review before deleting manually

Cleaned up 2 stale branch(es). 1 kept for review.
```

---

## Squash-merge detection

When `git branch -d` refuses, check whether the branch's patch is already in
the base branch even though the SHAs differ (squash or rebase merge). The
test is purely local — no `gh`/`az` calls — and compares patch identities
via `git cherry`.

```bash
# Determine the base branch; default to main if origin/HEAD isn't set.
base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
base="${base:-main}"

# Build a virtual squash commit: branch's tree, parented at the merge-base.
merge_base="$(git merge-base "$base" "$branch")"
virtual="$(git commit-tree "$(git rev-parse "${branch}^{tree}")" -p "$merge_base" -m _)"

# git cherry marks commits with `-` when their patch is already in base.
if [ "$(git cherry "$base" "$virtual" | head -n1 | cut -c1)" = "-" ]; then
    echo "squash-merged"
fi
```

This is the canonical "is this branch effectively merged?" test. It works
because `git cherry` compares patch IDs, not SHAs, so squash and rebase
merges — which change SHAs — are still detected as the same change.

If the check is indeterminate (e.g., `git commit-tree` fails, no merge-base
found), treat it as **not** squash-merged and keep the branch.

---

## Protected Branches

These branches are always protected and never deleted, regardless of
tracking status:

- `main`
- `master`
- `develop`
- `development`
- `release/*` and `releases/*` — any branch under these folders
  (e.g., `release/1.0`, `releases/2024-Q1`)
- The currently checked-out branch

---

## Safety Notes

- `git branch -d` is always tried first. Git refuses to delete unmerged
  branches, so straightforward cases are always safe.
- `git branch -D` is used **only** when **both** conditions hold:
  1. The branch's upstream tracking shows `[gone]` (origin deleted it), and
  2. The squash-merge detection confirms the branch's patch is already in
     the base branch.
  This matches the user's rule: "merged into main and deleted in origin ⇒
  delete local."
- Branches that are `[gone]` but whose work is **not** in the base branch are
  kept with a warning. Do not force-delete — the remote branch may have been
  deleted accidentally, and the unmerged work could otherwise be lost.
- Protected branches and the currently checked-out branch are never deleted,
  regardless of their tracking status.
- Only **local** branches are touched. The remote is never modified.
- Only branches whose tracking ref shows `: gone]` are candidates. Branches
  still present on origin are never touched, even if they appear stale.

---
name: branch-cleanup
description: >
  Prune remote tracking branches and delete local branches whose upstream
  no longer exists on the remote. Use when the user says "clean branches",
  "prune branches", "/prune", "delete stale branches", or "clean up old
  branches". Also triggered automatically after a push via smart-commit.
---

# Branch Cleanup

Fetch the latest remote state, identify **local** branches whose upstream tracking
branch has been deleted from origin, and remove them after confirmation. This only
deletes local branches — it never modifies or deletes anything on the remote.

## Process

Follow these steps every time:

1. **Fetch and prune remote tracking branches**
   - Run `git fetch --prune origin` — updates remote refs, removes tracking branches for deleted remote branches
   - Run `git branch -vv` — show all local branches with their tracking status

2. **Identify stale branches**
   - Parse `git branch -vv` output for branches showing `: gone]` — these had upstream branches that no longer exist
   - Use: `git branch -vv | grep ': gone]' | awk '{print $1}'`
   - Exclude protected branches: never touch `main`, `master`, `develop`, `release/*`, `releases/*`, or the currently checked-out branch
   - Get current branch: `git rev-parse --abbrev-ref HEAD`

3. **Show what would be deleted**
   - If no stale branches found, report "No stale branches — nothing to clean up" and stop
   - Otherwise list each stale branch with its last commit (one-liner):
     ```
     Stale branches (upstream deleted from origin):
       feature/old-thing     (last commit: abc1234 — 3 days ago)
       fix/resolved-issue    (last commit: def5678 — 1 week ago)
     ```
   - Show total count

4. **Confirm with the user**
   - Ask: "Delete these N branches? (They are fully merged — `git branch -d` will refuse if not.)"
   - Do NOT delete without explicit confirmation
   - **Exception**: when called automatically after a push (from smart-commit), still show the list but use a lighter touch: "Cleaned up N stale branches:" and auto-proceed since the branches are confirmed merged via -d

5. **Delete confirmed branches**
   - Use `git branch -d` (lowercase d) — this is safe because git refuses to delete unmerged branches
   - If `git branch -d` fails for a branch (unmerged), report it and skip — never escalate to `-D`
   - Report each deletion:
     ```
     ✓ Deleted feature/old-thing
     ✓ Deleted fix/resolved-issue
     ✗ Skipped bugfix/wip — has unmerged changes
     ```

6. **Summary**
   - "Cleaned up N stale branch(es). N skipped (unmerged)."

---

## Protected Branches

These branches are always protected and never deleted, regardless of tracking status:

- `main`
- `master`
- `development`
- `release/*` and `releases/*` — any branch under these folders (e.g., `release/1.0`, `releases/2024-Q1`)
- The currently checked-out branch

---

## Safety Notes

- Uses `git branch -d` (not `-D`) — git protects unmerged work
- Never deletes protected branches regardless of tracking status
- Never deletes the current branch
- Never deletes branches under `release/` or `releases/` folders
- Only deletes **local** branches — never modifies or removes anything on the remote
- Only targets branches whose remote tracking ref shows `: gone]`
- When in doubt, shows the branch list and asks — never deletes silently

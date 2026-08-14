---
name: branch-cleanup
description: Identify and safely remove stale local Git branches after reviewing upstream and merge evidence.
---

# Branch Cleanup

This skill owns branch deletion. Fetching and deletion change repository state, so preview the commands and request explicit approval before running them.

1. Inspect the current branch, remotes, upstream tracking, and protected branch names.
2. With approval, run `git fetch --all --prune`.
3. List local branches whose upstream is gone, excluding the current branch, `main`, `master`, `develop`, `development`, and `release/*`.
4. Show each candidate and its last commit.
5. Ask for explicit approval of the exact deletion set.
6. Prefer `git branch -d`. Use `-D` only when patch-identity evidence proves the work exists in the selected base branch and the user approves force deletion.
7. Report deleted and preserved branches.

Never delete remote branches or infer deletion consent from a missing upstream.

---
name: smart-commit
description: Review, stage, and create a focused Conventional Commit from an explicitly approved change set.
---

# Smart Commit

Repository guidance owns commit and security policy; this skill owns execution.

1. Inspect status and diffs without reading prohibited secret files.
2. Identify unrelated or suspicious changes and leave them unstaged.
3. Propose the exact file set and Conventional Commit message.
4. Obtain approval before staging or committing.
5. Stage exact paths, inspect the staged diff, run relevant validation, and commit.
6. Report the commit identifier and remaining changes.

Do not push. If branch cleanup is desired, hand off to `branch-cleanup`; do not delete branches here.

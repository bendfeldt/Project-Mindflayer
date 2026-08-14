# Repository Audit and Full Remediation

## Plan

1. Replace repository governance and documentation with implementation-focused guidance and three current ADRs.
2. Introduce a central distribution manifest and make lifecycle tooling consume it.
3. Harden installation, synchronization, drift detection, updates, store checks, permissions, and uninstall ownership semantics.
4. Consolidate and validate all ten skills, their metadata, references, and release-notes scripts.
5. Rebuild and extend tests for manifest completeness, portability, ownership, replacement, nested resources, and release-notes behavior.
6. Run static validation and the complete test suite, then remediate all confirmed failures.

## Constraints

- Preserve all ten public skill names and existing installer flags.
- Do not read prohibited secret or authentication files.
- Do not touch untracked `.codex/` content or unrelated worktree files.
- Do not deploy, publish, commit, or mutate external systems.
- The toolkit repository itself remains exempt from generated project layout installation.

## Lessons

- No process corrections recorded yet.

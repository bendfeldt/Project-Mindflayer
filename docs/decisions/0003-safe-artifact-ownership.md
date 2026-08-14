# ADR-0003: Safe artifact ownership

**Status:** Accepted  
**Date:** 2026-08-13

## Context

Installers and uninstallers share paths with user-authored assistant configuration. Path presence alone does not prove toolkit ownership.

## Decision

Existing files are preserved by default. Explicit `--force` authorization creates timestamped backups before replacement. Installations record managed paths and content fingerprints. Uninstall removes only recorded artifacts whose ownership can be verified; changed regular files are preserved unless explicit forced removal is requested, and forced removal creates a backup. Symlinks are removed only when their recorded target still matches.

## Consequences

- Join and update operations are non-destructive by default.
- Uninstall may leave user-modified artifacts for manual review.
- Lifecycle tools must maintain and consult ownership state.


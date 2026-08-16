#!/usr/bin/env python3
"""Produce a deterministic, content-free inventory of a repository scope."""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence


EXCLUDED_DIRECTORIES = frozenset(
    {
        ".git",
        ".hg",
        ".mypy_cache",
        ".next",
        ".pytest_cache",
        ".ruff_cache",
        ".svn",
        ".terraform",
        ".tox",
        ".venv",
        "__pycache__",
        "build",
        "coverage",
        "dist",
        "node_modules",
        "target",
        "venv",
        "vendor",
    }
)

LANGUAGE_EXTENSIONS = {
    ".bicep": "bicep",
    ".cs": "csharp",
    ".go": "go",
    ".hcl": "hcl",
    ".java": "java",
    ".js": "javascript",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".ps1": "powershell",
    ".py": "python",
    ".r": "r",
    ".rs": "rust",
    ".scala": "scala",
    ".sh": "shell",
    ".sql": "sql",
    ".tf": "hcl",
    ".ts": "typescript",
    ".tsx": "typescript",
}

SOURCE_DIRECTORY_NAMES = frozenset(
    {"app", "apps", "lib", "models", "notebooks", "pipelines", "src"}
)
TEST_DIRECTORY_NAMES = frozenset({"test", "tests"})
MIGRATION_DIRECTORY_NAMES = frozenset({"migration", "migrations"})

CONFIGURATION_NAMES = frozenset(
    {
        ".editorconfig",
        ".pre-commit-config.yaml",
        "azure-pipelines.yaml",
        "azure-pipelines.yml",
        "compose.yaml",
        "compose.yml",
        "databricks.yml",
        "dbt_project.yml",
        "docker-compose.yaml",
        "docker-compose.yml",
        "eslint.config.js",
        ".gitlab-ci.yml",
        "mkdocs.yml",
        "mypy.ini",
        "package.json",
        "pyproject.toml",
        "pytest.ini",
        "ruff.toml",
        "setup.cfg",
        "snowflake.yml",
        "tox.ini",
    }
)

DEPENDENCY_MANAGERS = {
    "cargo.lock": "cargo",
    "cargo.toml": "cargo",
    "composer.json": "composer",
    "gemfile": "bundler",
    "go.mod": "go-modules",
    "package-lock.json": "npm",
    "package.json": "npm",
    "pipfile": "pipenv",
    "pnpm-lock.yaml": "pnpm",
    "poetry.lock": "poetry",
    "requirements.txt": "pip",
    "uv.lock": "uv",
    "yarn.lock": "yarn",
}

DEPENDENCY_MANIFEST_NAMES = frozenset(DEPENDENCY_MANAGERS) | frozenset(
    {"pyproject.toml", "setup.cfg", "setup.py"}
)

GENERATED_FILE_SUFFIXES = (
    ".generated.py",
    ".min.css",
    ".min.js",
    ".pb.go",
)


class InventoryError(ValueError):
    """Raised for invalid inventory scope."""


def is_within(path: Path, root: Path) -> bool:
    """Return whether a resolved path is inside the resolved root."""
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def relative_path(path: Path, root: Path) -> str:
    """Return a portable repository-relative path."""
    return path.relative_to(root).as_posix()


def collect_repository_files(root: Path) -> tuple[list[Path], list[str]]:
    """Walk a repository without following links or generated directories."""
    files: list[Path] = []
    generated_directories: set[str] = set()

    for current, directory_names, file_names in os.walk(root, followlinks=False):
        current_path = Path(current)
        kept_directories: list[str] = []
        for directory_name in sorted(directory_names):
            directory_path = current_path / directory_name
            if directory_name in EXCLUDED_DIRECTORIES:
                generated_directories.add(relative_path(directory_path, root))
            elif directory_path.is_symlink():
                continue
            else:
                kept_directories.append(directory_name)
        directory_names[:] = kept_directories

        for file_name in sorted(file_names):
            file_path = current_path / file_name
            if file_path.is_symlink():
                continue
            files.append(file_path)

    return files, sorted(generated_directories)


def collect_scoped_files(root: Path, requested_files: Sequence[str]) -> list[Path]:
    """Resolve an explicit file list and reject traversal outside the root."""
    resolved_files: list[Path] = []
    seen: set[Path] = set()
    for requested_file in requested_files:
        candidate = Path(requested_file)
        if not candidate.is_absolute():
            candidate = root / candidate
        resolved = candidate.resolve()
        if not is_within(resolved, root):
            raise InventoryError(f"file is outside inventory root: {requested_file}")
        if not resolved.is_file():
            raise InventoryError(f"file does not exist or is not a regular file: {requested_file}")
        if resolved not in seen:
            resolved_files.append(resolved)
            seen.add(resolved)
    return sorted(resolved_files, key=lambda item: relative_path(item, root))


def directory_matches(paths: Iterable[Path], root: Path, names: frozenset[str]) -> list[str]:
    """Return directories with a recognized role."""
    matches: set[str] = set()
    for path in paths:
        relative = path.relative_to(root)
        for parent in relative.parents:
            if parent == Path("."):
                continue
            if parent.name.lower() in names:
                matches.add(parent.as_posix())
    return sorted(matches)


def inventory(root: Path, requested_files: Sequence[str] = ()) -> dict[str, object]:
    """Build deterministic repository inventory data without reading file contents."""
    resolved_root = root.resolve()
    if not resolved_root.is_dir():
        raise InventoryError(f"inventory root does not exist or is not a directory: {root}")

    if requested_files:
        files = collect_scoped_files(resolved_root, requested_files)
        generated_directories: list[str] = []
        scope = "files"
    else:
        files, generated_directories = collect_repository_files(resolved_root)
        scope = "repository"

    languages: set[str] = set()
    frameworks: set[str] = set()
    infrastructure: set[str] = set()
    ci: set[str] = set()
    dependency_managers: set[str] = set()
    data_platforms: set[str] = set()
    dependency_manifests: set[str] = set()
    configuration_files: set[str] = set()
    likely_generated_files: set[str] = set()
    file_types: Counter[str] = Counter()
    has_tests = False

    for file_path in files:
        relative = relative_path(file_path, resolved_root)
        relative_lower = relative.lower()
        name = file_path.name.lower()
        suffix = file_path.suffix.lower()

        if suffix in LANGUAGE_EXTENSIONS:
            languages.add(LANGUAGE_EXTENSIONS[suffix])
        file_types[suffix or "[no-extension]"] += 1

        if name in CONFIGURATION_NAMES or relative_lower.startswith(".github/workflows/"):
            configuration_files.add(relative)

        if name in DEPENDENCY_MANIFEST_NAMES:
            dependency_manifests.add(relative)
        manager = DEPENDENCY_MANAGERS.get(name)
        if manager:
            dependency_managers.add(manager)

        if name.endswith(GENERATED_FILE_SUFFIXES):
            likely_generated_files.add(relative)

        if name == "dbt_project.yml":
            frameworks.add("dbt")
        if suffix == ".ipynb":
            frameworks.add("jupyter")
        if name in {"pytest.ini", "conftest.py"}:
            frameworks.add("pytest")
        if "dags/" in relative_lower or relative_lower.startswith("dags/"):
            frameworks.add("airflow")

        if suffix == ".tf":
            infrastructure.add("terraform")
        if suffix == ".bicep":
            infrastructure.add("bicep")
        if name == "dockerfile" or name.startswith("dockerfile.") or "compose" in name:
            infrastructure.add("docker")

        if relative_lower.startswith(".github/workflows/"):
            ci.add("github-actions")
        if name in {"azure-pipelines.yml", "azure-pipelines.yaml"}:
            ci.add("azure-pipelines")
        if name == ".gitlab-ci.yml":
            ci.add("gitlab-ci")
        if name == "jenkinsfile":
            ci.add("jenkins")

        if name == "databricks.yml":
            data_platforms.add("databricks")
        if name == "snowflake.yml":
            data_platforms.add("snowflake")
        if suffix in {".pbip", ".pbir"} or ".semanticmodel/" in relative_lower:
            data_platforms.add("microsoft-fabric")

        path_parts = {part.lower() for part in file_path.relative_to(resolved_root).parts}
        if path_parts & TEST_DIRECTORY_NAMES or name.startswith("test_") or name.endswith("_test.py"):
            has_tests = True

    return {
        "ci": sorted(ci),
        "configuration_files": sorted(configuration_files),
        "data_platforms": sorted(data_platforms),
        "dependency_managers": sorted(dependency_managers),
        "dependency_manifests": sorted(dependency_manifests),
        "file_types": dict(sorted(file_types.items())),
        "files_scanned": len(files),
        "frameworks": sorted(frameworks),
        "infrastructure": sorted(infrastructure),
        "languages": sorted(languages),
        "likely_generated_directories": generated_directories,
        "likely_generated_files": sorted(likely_generated_files),
        "migration_directories": directory_matches(
            files, resolved_root, MIGRATION_DIRECTORY_NAMES
        ),
        "root": ".",
        "scope": scope,
        "source_directories": directory_matches(files, resolved_root, SOURCE_DIRECTORY_NAMES),
        "test_directories": directory_matches(files, resolved_root, TEST_DIRECTORY_NAMES),
        "tests": has_tests,
    }


def parse_args(arguments: Sequence[str]) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Produce a deterministic JSON inventory without reading file contents."
    )
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Inventory root")
    parser.add_argument(
        "--file",
        action="append",
        default=[],
        dest="files",
        help="Repository-relative file to inventory; repeat to restrict the scope",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the repository inventory CLI."""
    parsed = parse_args(arguments if arguments is not None else sys.argv[1:])
    try:
        result = inventory(parsed.root, parsed.files)
    except InventoryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Create a normalized project-install fixture for cross-runtime comparison."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_FILES = (
    Path("AGENTS.md"),
    Path("CLAUDE.md"),
    Path("GEMINI.md"),
    Path(".claude/settings.json"),
    Path(".gitignore"),
)


def normalized_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def installer_command(runtime: str) -> list[str]:
    common_values = [
        "claude,codex,gemini,cursor,copilot",
        "infrastructure,data-engineering",
        "terraform,python,sql",
        "Client",
        "cl",
    ]
    if runtime == "bash":
        return [
            "bash",
            str(ROOT / "install.sh"),
            "--project",
            "--tools",
            common_values[0],
            "--project-types",
            common_values[1],
            "--technologies",
            common_values[2],
            "--client",
            common_values[3],
            "--prefix",
            common_values[4],
            "--local",
        ]
    return [
        "pwsh",
        "-NoProfile",
        "-File",
        str(ROOT / "install.ps1"),
        "-Project",
        "-Tools",
        common_values[0],
        "-ProjectTypes",
        common_values[1],
        "-Technologies",
        common_values[2],
        "-Client",
        common_values[3],
        "-Prefix",
        common_values[4],
        "-Local",
    ]


def normalize_ownership(project: Path, ledger_path: Path) -> str:
    rows: list[str] = []
    project_resolved = project.resolve()
    for raw_line in normalized_text(ledger_path).splitlines():
        fields = raw_line.split("\t")
        if len(fields) != 3:
            raise ValueError(f"invalid ownership row: {raw_line}")
        raw_path, kind, proof = fields
        candidate = Path(raw_path)
        if candidate.is_absolute():
            try:
                raw_path = candidate.resolve().relative_to(project_resolved).as_posix()
            except ValueError as error:
                raise ValueError(f"project ownership path escapes fixture: {raw_path}") from error
        else:
            raw_path = raw_path.replace("\\", "/")
        rows.append("\t".join((raw_path, kind, proof.replace("\\", "/"))))
    return "\n".join(sorted(rows)) + "\n"


def create_fixture(runtime: str, output_directory: Path) -> None:
    if runtime not in {"bash", "powershell"}:
        raise ValueError(f"unsupported runtime: {runtime}")
    if output_directory.exists():
        raise FileExistsError(f"fixture output already exists: {output_directory}")
    with tempfile.TemporaryDirectory(prefix="mindflayer-parity-") as temporary_directory:
        temporary_root = Path(temporary_directory)
        project = temporary_root / "project"
        home = temporary_root / "home"
        project.mkdir()
        home.mkdir()
        environment = os.environ.copy()
        environment["HOME"] = str(home)
        result = subprocess.run(
            installer_command(runtime),
            cwd=project,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"{runtime} fixture install failed ({result.returncode}):\n"
                f"{result.stdout}\n{result.stderr}"
            )
        output_directory.mkdir(parents=True)
        for relative_path in FIXTURE_FILES:
            source_path = project / relative_path
            if not source_path.is_file():
                raise FileNotFoundError(f"fixture artifact missing: {relative_path}")
            destination_path = output_directory / relative_path
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            destination_path.write_text(normalized_text(source_path), encoding="utf-8", newline="\n")
        skill_root = project / ".agents" / "skills"
        if not skill_root.is_dir():
            raise FileNotFoundError("canonical project skill root is missing")
        for source_path in sorted(skill_root.rglob("*")):
            if not source_path.is_file() or source_path.is_symlink():
                continue
            relative_path = source_path.relative_to(project)
            destination_path = output_directory / relative_path
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_path, destination_path)
            if b"\x00" not in destination_path.read_bytes():
                destination_path.write_text(
                    normalized_text(destination_path), encoding="utf-8", newline="\n"
                )
        ownership_path = project / ".mindflayer-managed.tsv"
        (output_directory / "ownership.tsv").write_text(
            normalize_ownership(project, ownership_path), encoding="utf-8", newline="\n"
        )


def parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", choices=("bash", "powershell"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    parsed = parse_args(arguments)
    try:
        create_fixture(parsed.runtime, parsed.output.resolve())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

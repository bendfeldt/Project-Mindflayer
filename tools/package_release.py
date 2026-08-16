#!/usr/bin/env python3
"""Build a deterministic, platform-scoped Project Mindflayer release archive."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import os
import re
import tarfile
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence


PLATFORMS = frozenset({"linux", "macos", "windows"})
ARTIFACT_TYPES = frozenset(
    {
        "baseline",
        "decision",
        "document",
        "license",
        "manifest",
        "registry",
        "script",
        "setting",
        "shim",
        "skill",
        "skill-resource",
        "template",
    }
)
OWNERSHIP_CLASSES = frozenset({"managed-file", "managed-tree"})
CONSUMERS = frozenset(
    {
        "global",
        "global:claude",
        "global:codex",
        "global:copilot",
        "global:cursor",
        "global:gemini",
        "project",
        "project:claude",
        "project:claude:databricks",
        "project:claude:fabric",
        "project:claude:terraform",
        "project:gemini",
        "project:skills",
    }
)
VERSION_PATTERN = re.compile(r"v?[0-9]+\.[0-9]+\.[0-9]+")
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


@dataclass(frozen=True)
class ManifestRow:
    path: PurePosixPath
    version: str
    platforms: frozenset[str]


def parse_manifest(manifest_path: Path) -> tuple[ManifestRow, ...]:
    """Parse and validate the canonical six-field manifest."""
    rows: list[ManifestRow] = []
    seen_paths: set[PurePosixPath] = set()
    for line_number, raw_line in enumerate(
        manifest_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw_line or raw_line.startswith("#"):
            continue
        fields = raw_line.split("\t")
        if len(fields) != 6:
            raise ValueError(f"manifest line {line_number} must contain six fields")
        raw_path, artifact_type, version, raw_consumers, ownership, raw_platforms = fields
        path = PurePosixPath(raw_path)
        if (
            not raw_path
            or raw_path.startswith("/")
            or "\\" in raw_path
            or any(part in {"", ".", ".."} for part in raw_path.split("/"))
        ):
            raise ValueError(f"manifest line {line_number} has unsafe path: {raw_path}")
        if path in seen_paths:
            raise ValueError(f"manifest line {line_number} duplicates path: {raw_path}")
        if artifact_type not in ARTIFACT_TYPES:
            raise ValueError(f"manifest line {line_number} has invalid type: {artifact_type}")
        if not VERSION_PATTERN.fullmatch(version):
            raise ValueError(f"manifest line {line_number} has invalid version: {version}")
        consumers_list = raw_consumers.split(",")
        consumers = frozenset(consumers_list)
        if (
            not consumers
            or len(consumers) != len(consumers_list)
            or not consumers <= CONSUMERS
        ):
            raise ValueError(
                f"manifest line {line_number} has invalid consumers: {raw_consumers}"
            )
        if ownership not in OWNERSHIP_CLASSES:
            raise ValueError(
                f"manifest line {line_number} has invalid ownership: {ownership}"
            )
        platforms_list = raw_platforms.split(",")
        platforms = frozenset(platforms_list)
        if (
            not platforms
            or len(platforms) != len(platforms_list)
            or not platforms <= PLATFORMS
        ):
            raise ValueError(
                f"manifest line {line_number} has invalid platforms: {raw_platforms}"
            )
        seen_paths.add(path)
        rows.append(ManifestRow(path=path, version=version, platforms=platforms))
    if not rows:
        raise ValueError("manifest contains no distributable rows")
    return tuple(rows)


def selected_paths(rows: Iterable[ManifestRow], platform: str) -> tuple[PurePosixPath, ...]:
    """Return the canonical artifact projection for one target platform."""
    return tuple(row.path for row in rows if platform in row.platforms)


def archive_members(repository_root: Path, paths: Iterable[PurePosixPath]) -> list[Path]:
    """Resolve selected source files and reject missing or non-regular members."""
    members: list[Path] = []
    for relative_path in paths:
        source_path = repository_root.joinpath(*relative_path.parts)
        if not source_path.is_file() or source_path.is_symlink():
            raise ValueError(f"release source is missing or not a regular file: {relative_path}")
        members.append(source_path)
    return members


def normalized_mode(path: Path) -> int:
    """Return stable executable or regular-file permissions."""
    return 0o755 if os.access(path, os.X_OK) else 0o644


def build_tar_gz(
    output_path: Path,
    repository_root: Path,
    root_name: str,
    members: Sequence[Path],
    source_date_epoch: int,
) -> None:
    """Write a deterministic gzip-compressed tar archive."""
    with output_path.open("xb") as output_file:
        with gzip.GzipFile(fileobj=output_file, mode="wb", mtime=source_date_epoch) as gzip_file:
            with tarfile.open(fileobj=gzip_file, mode="w") as archive:
                for source_path in members:
                    relative_path = source_path.relative_to(repository_root).as_posix()
                    content = source_path.read_bytes()
                    info = tarfile.TarInfo(f"{root_name}/{relative_path}")
                    info.size = len(content)
                    info.mode = normalized_mode(source_path)
                    info.mtime = source_date_epoch
                    info.uid = 0
                    info.gid = 0
                    info.uname = "root"
                    info.gname = "root"
                    archive.addfile(info, io.BytesIO(content))


def build_zip(
    output_path: Path,
    repository_root: Path,
    root_name: str,
    members: Sequence[Path],
) -> None:
    """Write a deterministic ZIP archive."""
    with zipfile.ZipFile(output_path, mode="x", compression=zipfile.ZIP_DEFLATED) as archive:
        for source_path in members:
            relative_path = source_path.relative_to(repository_root).as_posix()
            info = zipfile.ZipInfo(f"{root_name}/{relative_path}", FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = normalized_mode(source_path) << 16
            archive.writestr(info, source_path.read_bytes())


def write_checksum(archive_path: Path) -> Path:
    """Write a non-overwriting SHA-256 sidecar for the archive."""
    checksum = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    checksum_path = archive_path.with_name(f"{archive_path.name}.sha256")
    with checksum_path.open("x", encoding="ascii") as checksum_file:
        checksum_file.write(f"{checksum}  {archive_path.name}\n")
    return checksum_path


def build_release(
    repository_root: Path,
    output_directory: Path,
    platform: str,
    version: str,
    source_date_epoch: int,
) -> tuple[Path, Path]:
    """Build one platform archive and checksum sidecar."""
    if platform not in PLATFORMS:
        raise ValueError(f"unsupported platform: {platform}")
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("version must use vMAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH")
    normalized_version = version.removeprefix("v")
    manifest_path = repository_root / "manifest.tsv"
    rows = parse_manifest(manifest_path)
    paths = selected_paths(rows, platform)
    required_installer = PurePosixPath("install.ps1" if platform == "windows" else "install.sh")
    if PurePosixPath("manifest.tsv") not in paths or required_installer not in paths:
        raise ValueError(f"manifest projection for {platform} lacks its manifest or installer")
    installer_row = next(row for row in rows if row.path == required_installer)
    if installer_row.version != normalized_version:
        raise ValueError(
            f"release version {normalized_version} does not match "
            f"{required_installer} lifecycle version {installer_row.version}"
        )
    members = archive_members(repository_root, paths)
    root_name = f"project-mindflayer-{normalized_version}-{platform}"
    suffix = ".zip" if platform == "windows" else ".tar.gz"
    output_directory.mkdir(parents=True, exist_ok=True)
    archive_path = output_directory / f"{root_name}{suffix}"
    if archive_path.exists() or archive_path.with_name(f"{archive_path.name}.sha256").exists():
        raise FileExistsError(f"release output already exists: {archive_path}")
    if platform == "windows":
        build_zip(archive_path, repository_root, root_name, members)
    else:
        build_tar_gz(
            archive_path,
            repository_root,
            root_name,
            members,
            source_date_epoch,
        )
    return archive_path, write_checksum(archive_path)


def parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).parents[1])
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--platform", choices=sorted(PLATFORMS), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--source-date-epoch",
        type=int,
        default=int(os.environ.get("SOURCE_DATE_EPOCH", "0")),
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    parsed = parse_args(arguments)
    try:
        archive_path, checksum_path = build_release(
            repository_root=parsed.repository_root.resolve(),
            output_directory=parsed.output_directory.resolve(),
            platform=parsed.platform,
            version=parsed.version,
            source_date_epoch=parsed.source_date_epoch,
        )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=os.sys.stderr)
        return 1
    print(archive_path)
    print(checksum_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

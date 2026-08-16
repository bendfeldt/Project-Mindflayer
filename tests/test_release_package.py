from __future__ import annotations

import hashlib
import importlib.util
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "package_release.py"
SPEC = importlib.util.spec_from_file_location("package_release", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SCRIPT}")
PACKAGE_RELEASE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PACKAGE_RELEASE
SPEC.loader.exec_module(PACKAGE_RELEASE)


class ReleasePackageTests(unittest.TestCase):
    def archive_names(self, archive_path: Path) -> set[str]:
        if archive_path.suffix == ".zip":
            with zipfile.ZipFile(archive_path) as archive:
                return set(archive.namelist())
        with tarfile.open(archive_path, mode="r:gz") as archive:
            return set(archive.getnames())

    def test_platform_archives_are_exact_manifest_projections(self) -> None:
        rows = PACKAGE_RELEASE.parse_manifest(ROOT / "manifest.tsv")
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_root = Path(temporary_directory)
            for platform in sorted(PACKAGE_RELEASE.PLATFORMS):
                platform_output = output_root / platform
                archive_path, checksum_path = PACKAGE_RELEASE.build_release(
                    ROOT, platform_output, platform, "v3.6.0", 0
                )
                root_name = f"project-mindflayer-3.6.0-{platform}"
                expected_names = {
                    f"{root_name}/{path.as_posix()}"
                    for path in PACKAGE_RELEASE.selected_paths(rows, platform)
                }
                self.assertEqual(self.archive_names(archive_path), expected_names)
                checksum, file_name = checksum_path.read_text(encoding="ascii").split()
                self.assertEqual(file_name, archive_path.name)
                self.assertEqual(checksum, hashlib.sha256(archive_path.read_bytes()).hexdigest())

    def test_platform_archives_exclude_foreign_runtime_and_noise(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_root = Path(temporary_directory)
            linux_archive, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "linux", "linux", "3.6.0", 0
            )
            windows_archive, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "windows", "windows", "3.6.0", 0
            )
            linux_names = self.archive_names(linux_archive)
            windows_names = self.archive_names(windows_archive)
            self.assertFalse(any(name.endswith(".ps1") for name in linux_names))
            self.assertFalse(any(name.endswith(".sh") for name in windows_names))
            for names in (linux_names, windows_names):
                self.assertFalse(any("/__pycache__/" in name for name in names))
                self.assertFalse(any("/tests/" in name for name in names))

    def test_existing_release_output_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_root = Path(temporary_directory)
            PACKAGE_RELEASE.build_release(ROOT, output_root, "linux", "v3.6.0", 0)
            with self.assertRaises(FileExistsError):
                PACKAGE_RELEASE.build_release(ROOT, output_root, "linux", "v3.6.0", 0)

    def test_release_archives_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_root = Path(temporary_directory)
            first, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "first", "linux", "v3.6.0", 123456789
            )
            second, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "second", "linux", "v3.6.0", 123456789
            )
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_manifest_traversal_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest_path = Path(temporary_directory) / "manifest.tsv"
            manifest_path.write_text(
                "../escape\tscript\t1.0.0\tglobal\tmanaged-file\tlinux\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "unsafe path"):
                PACKAGE_RELEASE.parse_manifest(manifest_path)

    def test_release_workflow_is_keyless_and_non_overwriting(self) -> None:
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('tags:\n      - "v[0-9]+.[0-9]+.[0-9]+"', workflow)
        self.assertIn("id-token: write", workflow)
        self.assertIn("cosign sign-blob --yes --bundle", workflow)
        self.assertIn("Refuse release replacement", workflow)
        self.assertIn("matrix:\n        platform: [linux, macos, windows]", workflow)

    def test_public_installation_does_not_use_mutable_main(self) -> None:
        documentation_paths = (
            ROOT / "README.md",
            ROOT / "how-to-guide.md",
            ROOT / "docs/system-requirements.md",
            ROOT / "docs/architecture.md",
            ROOT / "skills/setup-repo/SKILL.md",
        )
        for documentation_path in documentation_paths:
            content = documentation_path.read_text(encoding="utf-8")
            self.assertNotIn(
                "raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main",
                content,
                documentation_path,
            )
        readme = documentation_paths[0].read_text(encoding="utf-8")
        self.assertIn("cosign verify-blob", readme)
        self.assertIn("refs/tags/v${version}", readme)


if __name__ == "__main__":
    unittest.main()

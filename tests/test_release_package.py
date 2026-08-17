from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
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

RELEASE_VERSION = "3.7.0"


class ReleasePackageTests(unittest.TestCase):
    @staticmethod
    def fenced_block(path: Path, language: str, occurrence: int = 0) -> str:
        content = path.read_text(encoding="utf-8")
        marker = f"```{language}\n"
        start = -1
        for _ in range(occurrence + 1):
            start = content.index(marker, start + 1)
        start += len(marker)
        end = content.index("\n```", start)
        return content[start:end]

    @staticmethod
    def write_executable(path: Path, content: str) -> None:
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def run_unix_bootstrap(
        self,
        temporary_root: Path,
        *,
        arguments: tuple[str, ...] = ("--global", "--tools", "codex"),
        system: str = "Linux",
        architecture: str = "x86_64",
        has_cosign: bool = True,
        hash_exit: int = 0,
        cosign_exit: int = 0,
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path, str]:
        caller = temporary_root / "caller"
        fake_bin = temporary_root / "bin"
        staging_root = temporary_root / "staging"
        log_path = temporary_root / "commands.log"
        caller.mkdir()
        fake_bin.mkdir()
        staging_root.mkdir()

        self.write_executable(
            fake_bin / "uname",
            f"""#!/bin/sh
case "$1" in
  -s) printf '%s\\n' '{system}' ;;
  -m) printf '%s\\n' '{architecture}' ;;
esac
""",
        )
        self.write_executable(
            fake_bin / "curl",
            """#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    shift
    output="$1"
  fi
  shift
done
printf 'curl %s\\n' "$output" >> "$FAKE_COMMAND_LOG"
case "$output" in
  */cosign)
    printf '#!/bin/sh\\nprintf "cosign %%s\\\\n" "$*" >> "$FAKE_COMMAND_LOG"\\nexit "$FAKE_COSIGN_EXIT"\\n' > "$output"
    ;;
  *.sha256)
    printf '%064d  fixture\\n' 0 | tr '0' 'f' > "$output"
    ;;
  *)
    : > "$output"
    ;;
esac
""",
        )
        self.write_executable(
            fake_bin / "shasum",
            """#!/bin/sh
printf 'hash\\n' >> "$FAKE_COMMAND_LOG"
[ "$FAKE_HASH_EXIT" -eq 0 ] || exit "$FAKE_HASH_EXIT"
for argument in "$@"; do verified_file="$argument"; done
case "$verified_file" in
  */cosign) hash=8b24b946dd5809c6bd93de08033bcf6bc0ed7d336b7785787c080f574b89249b ;;
  *) hash=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff ;;
esac
printf '%s  %s\\n' "$hash" "$verified_file"
""",
        )
        self.write_executable(
            fake_bin / "tar",
            """#!/bin/sh
set -eu
printf 'tar\\n' >> "$FAKE_COMMAND_LOG"
archive=
destination=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -xzf) shift; archive="$1" ;;
    -C) shift; destination="$1" ;;
  esac
  shift
done
root_name="$(basename "$archive" .tar.gz)"
bundle_root="$destination/$root_name"
mkdir -p "$bundle_root"
cat > "$bundle_root/install.sh" <<'INSTALL'
#!/bin/sh
printf 'install %s\\n' "$*" >> "$FAKE_COMMAND_LOG"
printf 'install-pwd %s\\n' "$PWD" >> "$FAKE_COMMAND_LOG"
INSTALL
chmod 0700 "$bundle_root/install.sh"
""",
        )
        if has_cosign:
            self.write_executable(
                fake_bin / "cosign",
                """#!/bin/sh
printf 'cosign %s\\n' "$*" >> "$FAKE_COMMAND_LOG"
exit "$FAKE_COSIGN_EXIT"
""",
            )

        environment = os.environ.copy()
        environment.update(
            {
                "FAKE_COMMAND_LOG": str(log_path),
                "FAKE_COSIGN_EXIT": str(cosign_exit),
                "FAKE_HASH_EXIT": str(hash_exit),
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "TMPDIR": str(staging_root),
            }
        )
        result = subprocess.run(
            ["bash", str(ROOT / "bootstrap.sh"), *arguments],
            cwd=caller,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        log = log_path.read_text(encoding="utf-8") if log_path.exists() else ""
        return result, caller, staging_root, log

    def run_powershell_bootstrap(
        self, temporary_root: Path, *, installer_exit: int = 0
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path, str]:
        caller = temporary_root / "caller"
        fake_bin = temporary_root / "bin"
        staging_root = temporary_root / "staging"
        log_path = temporary_root / "commands.log"
        harness_path = temporary_root / "harness.ps1"
        caller.mkdir()
        fake_bin.mkdir()
        staging_root.mkdir()

        self.write_executable(
            fake_bin / "cosign",
            "#!/bin/sh\nprintf 'cosign %s\\n' \"$*\" >> \"$FAKE_COMMAND_LOG\"\nexit 0\n",
        )
        harness_path.write_text(
            r"""
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile)
    [IO.File]::AppendAllText($env:FAKE_COMMAND_LOG, "download $OutFile`n")
    if ($OutFile.EndsWith('.sha256')) {
        [IO.File]::WriteAllText($OutFile, (('f' * 64) + "  fixture`n"))
    }
    else {
        [IO.File]::WriteAllText($OutFile, '')
    }
}
function Get-FileHash {
    param([string]$Path, [string]$Algorithm)
    [pscustomobject]@{ Hash = ('f' * 64) }
}
function Expand-Archive {
    param([string]$LiteralPath, [string]$DestinationPath)
    $bundleRoot = Join-Path $DestinationPath 'project-mindflayer-3.7.0-windows'
    [void](New-Item -ItemType Directory -Path $bundleRoot)
    $installer = @'
param([switch]$Project, [string]$Tools, [switch]$Force, [switch]$Local)
[IO.File]::AppendAllText($env:FAKE_COMMAND_LOG, "$Project|$Tools|$Force|$Local|$PWD`n")
exit [int]$env:FAKE_INSTALLER_EXIT
'@
    [IO.File]::WriteAllText((Join-Path $bundleRoot 'install.ps1'), $installer)
}
& $env:BOOTSTRAP_PATH -Local -Project -Tools codex -Force
""",
            encoding="utf-8",
        )

        environment = os.environ.copy()
        environment.update(
            {
                "BOOTSTRAP_PATH": str(ROOT / "bootstrap.ps1"),
                "FAKE_COMMAND_LOG": str(log_path),
                "FAKE_INSTALLER_EXIT": str(installer_exit),
                "PATH": f"{fake_bin}:{environment['PATH']}",
                "PROCESSOR_ARCHITECTURE": "AMD64",
                "TMPDIR": str(staging_root),
            }
        )
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-File", str(harness_path)],
            cwd=caller,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        log = log_path.read_text(encoding="utf-8") if log_path.exists() else ""
        return result, caller, staging_root, log

    @staticmethod
    def archive_names(archive_path: Path) -> set[str]:
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
                    ROOT, platform_output, platform, RELEASE_VERSION, 0
                )
                root_name = f"project-mindflayer-{RELEASE_VERSION}-{platform}"
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
                ROOT, output_root / "linux", "linux", RELEASE_VERSION, 0
            )
            windows_archive, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "windows", "windows", RELEASE_VERSION, 0
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
            PACKAGE_RELEASE.build_release(ROOT, output_root, "linux", RELEASE_VERSION, 0)
            with self.assertRaises(FileExistsError):
                PACKAGE_RELEASE.build_release(ROOT, output_root, "linux", RELEASE_VERSION, 0)

    def test_release_archives_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_root = Path(temporary_directory)
            first, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "first", "linux", RELEASE_VERSION, 123456789
            )
            second, _ = PACKAGE_RELEASE.build_release(
                ROOT, output_root / "second", "linux", RELEASE_VERSION, 123456789
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

    def test_release_workflow_signs_archives_and_bootstraps(self) -> None:
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('tags:\n      - "v[0-9]+.[0-9]+.[0-9]+"', workflow)
        self.assertIn("id-token: write", workflow)
        self.assertIn("cosign sign-blob --yes --bundle", workflow)
        self.assertIn("bootstrap.sh.sha256", workflow)
        self.assertIn("bootstrap.ps1.sha256", workflow)
        self.assertIn("needs: [package, bootstrap]", workflow)
        self.assertIn("Refuse release replacement", workflow)
        self.assertIn("matrix:\n        platform: [linux, macos, windows]", workflow)

    def test_documented_installers_are_single_line_release_commands(self) -> None:
        documentation_paths = (
            ROOT / "README.md",
            ROOT / "how-to-guide.md",
            ROOT / "docs/system-requirements.md",
            ROOT / "skills/setup-repo/SKILL.md",
        )
        for documentation_path in documentation_paths:
            content = documentation_path.read_text(encoding="utf-8")
            unix = self.fenced_block(documentation_path, "bash")
            windows = self.fenced_block(documentation_path, "powershell")
            self.assertEqual(len(unix.splitlines()), 1, documentation_path)
            self.assertEqual(len(windows.splitlines()), 1, documentation_path)
            self.assertIn("releases/latest/download/bootstrap.sh", unix, documentation_path)
            self.assertIn("releases/latest/download/bootstrap.ps1", windows, documentation_path)
            self.assertNotIn("raw.githubusercontent.com", content, documentation_path)
            self.assertNotIn("cosign verify-blob", content, documentation_path)
            self.assertNotIn("verified-release-directory", content, documentation_path)

    def test_bootstrap_versions_and_verification_policy(self) -> None:
        bash = (ROOT / "bootstrap.sh").read_text(encoding="utf-8")
        powershell = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8")
        self.assertIn(f'VERSION="{RELEASE_VERSION}"', bash)
        self.assertIn(f"$script:Version = '{RELEASE_VERSION}'", powershell)
        for content in (bash, powershell):
            self.assertIn("verify-blob", content)
            self.assertIn("token.actions.githubusercontent.com", content)
            self.assertIn("2.4.1", content)
        self.assertIn("cosign-windows-amd64.exe", powershell)
        self.assertIn("@PSBoundParameters", powershell)

    def test_unix_bootstrap_forwards_arguments_and_preserves_caller(self) -> None:
        arguments = ("--project", "--tools", "codex", "--force")
        for has_cosign in (True, False):
            with self.subTest(has_cosign=has_cosign), tempfile.TemporaryDirectory() as directory:
                result, caller, staging_root, log = self.run_unix_bootstrap(
                    Path(directory), arguments=arguments, has_cosign=has_cosign
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(list(caller.iterdir()), [])
                self.assertEqual(list(staging_root.iterdir()), [])
                self.assertIn("install --project --tools codex --force\n", log)
                self.assertIn(f"install-pwd {caller.resolve()}\n", log)
                if not has_cosign:
                    self.assertIn("/cosign\n", log)

    def test_unix_bootstrap_verification_failures_stop_before_extraction(self) -> None:
        scenarios = (
            {"has_cosign": False, "hash_exit": 1, "cosign_exit": 0},
            {"has_cosign": True, "hash_exit": 1, "cosign_exit": 0},
            {"has_cosign": True, "hash_exit": 0, "cosign_exit": 1},
        )
        for scenario in scenarios:
            with self.subTest(**scenario), tempfile.TemporaryDirectory() as directory:
                result, caller, staging_root, log = self.run_unix_bootstrap(
                    Path(directory), **scenario
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(caller.iterdir()), [])
                self.assertEqual(list(staging_root.iterdir()), [])
                self.assertNotIn("tar\n", log)
                self.assertNotIn("install ", log)

    def test_unix_bootstrap_rejects_unsupported_host_before_download(self) -> None:
        scenarios = (
            {"system": "FreeBSD", "architecture": "x86_64"},
            {"system": "Linux", "architecture": "s390x"},
        )
        for scenario in scenarios:
            with self.subTest(**scenario), tempfile.TemporaryDirectory() as directory:
                result, caller, staging_root, log = self.run_unix_bootstrap(
                    Path(directory), **scenario
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(caller.iterdir()), [])
                self.assertEqual(list(staging_root.iterdir()), [])
                self.assertNotIn("curl ", log)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is unavailable")
    def test_powershell_bootstrap_forwards_named_parameters_and_cleans_staging(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, caller, staging_root, log = self.run_powershell_bootstrap(Path(directory))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(caller.iterdir()), [])
            self.assertEqual(list(staging_root.iterdir()), [])
            self.assertIn("True|codex|True|True|", log)
            self.assertIn(str(caller.resolve()), log)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is unavailable")
    def test_powershell_bootstrap_propagates_installer_failure_and_cleans_staging(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, caller, staging_root, _ = self.run_powershell_bootstrap(
                Path(directory), installer_exit=7
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(caller.iterdir()), [])
            self.assertEqual(list(staging_root.iterdir()), [])
            self.assertIn("installer failed with exit code 7", result.stderr)


if __name__ == "__main__":
    unittest.main()

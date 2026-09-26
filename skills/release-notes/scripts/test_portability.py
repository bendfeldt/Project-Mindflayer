#!/usr/bin/env python3
"""Dependency-free tests for behavior that differs between platforms.

The skill is authored on macOS but runs wherever the release is cut. Two things
break silently when it moves: text written in the locale encoding, and command
shims that CreateProcess cannot launch. Both are asserted here without needing
the platform that exhibits them.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from config import (
    ToolError,
    read_json,
    read_text,
    resolve_command,
    resolve_email,
    run_capture,
    supported_email_tools,
    write_json,
    write_text,
)
from make_email_draft import build_draft, read_html_body, read_subject
from merge_release import STRINGS, render_html

ARTIFACT = {
    "repo": "Salgsrapportering",
    "provider": "ado",
    "org": "contoso",
    "project": "Team Projekt Æ",
    "head": "releases/rel_1",
    "pull_request": {"id": "1", "url": "https://example.invalid/pullrequest/1"},
    "parent": {"id": "100", "type": "User Story",
               "url": "https://example.invalid/workitems/100"},
    "tasks": [
        {"id": "1001", "title": "Model: Salgstal ændret",
         "url": "https://example.invalid/workitems/1001"},
    ],
    "unclaimed_folders": ["løsning/Økonomi.Report"],
}


class TextArtifactTests(unittest.TestCase):
    """Artifacts are handed between scripts, so their bytes must not vary."""

    def test_text_is_written_as_utf8_with_lf_endings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "body.html"
            write_text(path, "<p>Ændret\nØkonomi</p>\n")

            raw = path.read_bytes()
            self.assertIn("Ændret".encode("utf-8"), raw)
            self.assertNotIn(b"\r\n", raw)
            self.assertEqual(read_text(path), "<p>Ændret\nØkonomi</p>\n")

    def test_json_round_trips_without_ascii_escaping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            payload = {"tasks": {"1001": "Salgstal ændret"}}
            write_json(path, payload)

            self.assertIn("ændret".encode("utf-8"), path.read_bytes())
            self.assertEqual(read_json(path), payload)

    def test_rendered_release_feeds_the_draft_generator(self) -> None:
        """merge_release writes what make_email_draft reads as strict UTF-8."""
        strings = STRINGS["da"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subject_path = root / "subject.txt"
            body_path = root / "body.html"
            write_text(body_path, render_html("rel_1", [ARTIFACT], strings))
            write_text(subject_path, strings["subject"].format(release="rel_1"))

            subject = read_subject(subject_path)
            body = read_html_body(body_path)
            draft = build_draft(subject, body)

            self.assertIn("frist", subject)
            self.assertIn("Salgstal ændret", body)
            self.assertIn("Økonomi.Report", body)
            self.assertIn("ændret".encode("utf-8"), body_path.read_bytes())
            self.assertTrue(draft.endswith(b"\r\n"))


class ExecutableResolutionTests(unittest.TestCase):
    """`az` is `az.cmd` on Windows, which bare subprocess cannot launch."""

    def test_resolved_path_is_used_verbatim_for_real_executables(self) -> None:
        with mock.patch("config.shutil.which", return_value="/usr/bin/git"):
            command = resolve_command(["git", "rev-parse", "--show-toplevel"])

        self.assertFalse(command.shell)
        self.assertEqual(
            command.args, ["/usr/bin/git", "rev-parse", "--show-toplevel"]
        )

    def test_command_shims_are_quoted_for_the_command_processor(self) -> None:
        shim = r"C:\Program Files\Azure CLI\wbin\az.cmd"
        url = "https://dev.azure.com/contoso/_apis/wit/workitems/1?api-version=7.0&$expand=all"
        with mock.patch("config.ON_WINDOWS", True), \
                mock.patch("config.shutil.which", return_value=shim):
            command = resolve_command(["az", "rest", "--url", url, "-o", "json"])

        self.assertTrue(command.shell)
        self.assertEqual(
            command.args,
            f'"{shim}" "rest" "--url" "{url}" "-o" "json"',
        )

    def test_query_string_ampersands_survive_the_shim(self) -> None:
        """Every Azure DevOps REST URL carries `&`; quoting must not split it."""
        with mock.patch("config.ON_WINDOWS", True), \
                mock.patch("config.shutil.which", return_value=r"C:\wbin\az.cmd"):
            command = resolve_command(
                ["az", "rest", "--url", "https://x/_apis/wit?ids=1&api-version=7.0"]
            )

        self.assertIn('"https://x/_apis/wit?ids=1&api-version=7.0"', command.args)

    def test_percent_encoded_project_names_reach_the_shim(self) -> None:
        """Azure DevOps percent-encodes every project name in its REST URLs."""
        url = "https://dev.azure.com/contoso/Team%20Projekt/_apis/wit/workitems/1"
        with mock.patch("config.ON_WINDOWS", True), \
                mock.patch("config.shutil.which", return_value=r"C:\wbin\az.cmd"):
            self.assertIn(url, resolve_command(["az", "rest", "--url", url]).args)

    def test_a_shim_receives_every_argument_intact(self) -> None:
        """Run a real shim and inspect the arguments that actually arrive.

        Quoting a command line is easy to get wrong in a way no string
        comparison catches: an earlier revision refused `&` outright, which
        would have rejected every Azure DevOps REST URL. So execute a shim and
        assert on its argv rather than on the line handed to it.

        This covers the characters `cmd.exe` and the POSIX shell treat alike —
        the separators (`&`), spaces, and percent-encoding. It deliberately
        leaves out `$`, which `cmd.exe` treats as an ordinary character but a
        POSIX shell expands: `$expand` is a real Azure DevOps parameter, and
        only Windows ever reaches this branch, so a POSIX host cannot stand in
        for that one. `test_command_shims_are_quoted_for_the_command_processor`
        asserts `$expand` survives into the command line instead.
        """
        url = (
            "https://dev.azure.com/contoso/Team%20Projekt%20%C3%86/_apis/wit"
            "/workitems?ids=1,2&api-version=7.0&fields=System.Title"
        )
        with tempfile.TemporaryDirectory() as directory:
            shim = Path(directory) / "az.cmd"
            shim.write_text(
                '#!/bin/sh\nprintf \'%s\\n\' "$@"\n', encoding="utf-8"
            )
            shim.chmod(0o755)

            with mock.patch("config.ON_WINDOWS", True), \
                    mock.patch("config.shutil.which", return_value=str(shim)):
                proc = run_capture([
                    "az", "rest", "--url", url, "--headers",
                    "Content-Type=application/json-patch+json", "-o", "json",
                ])

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            proc.stdout.splitlines(),
            [
                "rest",
                "--url",
                url,
                "--headers",
                "Content-Type=application/json-patch+json",
                "-o",
                "json",
            ],
        )

    def test_a_trailing_backslash_cannot_escape_the_closing_quote(self) -> None:
        """The program behind the shim reads `\\"` as a literal quote."""
        with mock.patch("config.ON_WINDOWS", True), \
                mock.patch("config.shutil.which", return_value=r"C:\wbin\az.cmd"):
            command = resolve_command(
                ["az", "rest", "--body", r"@C:\Temp\run\\", "-o", "json"]
            )

        self.assertIn(r'"@C:\Temp\run\\\\"', command.args)
        self.assertTrue(command.args.endswith('"json"'))

    def test_unquotable_shim_arguments_are_refused(self) -> None:
        with mock.patch("config.ON_WINDOWS", True), \
                mock.patch("config.shutil.which", return_value=r"C:\wbin\az.cmd"):
            with self.assertRaises(ToolError) as caught:
                resolve_command(["az", "rest", "--url", 'https://x/?a="b"'])
        self.assertIn("command shim", str(caught.exception.code))

    def test_shims_are_not_shell_invoked_off_windows(self) -> None:
        with mock.patch("config.shutil.which", return_value="/opt/vendor/az.cmd"):
            command = resolve_command(["az", "account", "show"])

        self.assertFalse(command.shell)
        self.assertEqual(command.args, ["/opt/vendor/az.cmd", "account", "show"])

    def test_missing_tool_names_the_tool(self) -> None:
        with mock.patch("config.shutil.which", return_value=None):
            with self.assertRaises(ToolError) as caught:
                resolve_command(["az", "account", "show"])
        self.assertIn("Azure CLI (az)", str(caught.exception.code))

    def test_output_is_decoded_as_utf8_whatever_the_locale_is(self) -> None:
        # The emitted bytes are spelled as an escape so that argv itself stays
        # ASCII: a POSIX host in the C locale cannot encode a non-ASCII
        # argument, which would fail this test for a reason unrelated to how
        # the output is decoded.
        proc = run_capture([
            sys.executable, "-c",
            r"import sys; sys.stdout.buffer.write(b'\xc3\xa6ndret\n')",
        ])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), "ændret")


class EmailToolResolutionTests(unittest.TestCase):
    """An engagement file outlives the machine it was bootstrapped on."""

    def test_supported_tools_per_platform(self) -> None:
        self.assertEqual(supported_email_tools("darwin"), {"outlook-macos", "eml"})
        self.assertEqual(supported_email_tools("linux"), {"eml"})
        self.assertEqual(supported_email_tools("win32"), {"eml"})
        self.assertEqual(supported_email_tools("freebsd14"), {"none"})

    def test_outlook_configured_on_macos_falls_back_elsewhere(self) -> None:
        for platform in ("linux", "win32"):
            with self.subTest(platform=platform):
                resolved = resolve_email({"tool": "outlook-macos"}, platform)
                self.assertEqual(resolved["tool"], "eml")
                self.assertEqual(resolved["configured_tool"], "outlook-macos")
                self.assertTrue(resolved["platform_override"])

    def test_eml_is_selectable_on_macos_without_outlook(self) -> None:
        resolved = resolve_email({"tool": "eml"}, "darwin")
        self.assertEqual(resolved["tool"], "eml")
        self.assertFalse(resolved["platform_override"])

    def test_absent_configuration_takes_the_platform_default(self) -> None:
        self.assertEqual(resolve_email(None, "darwin")["tool"], "outlook-macos")
        self.assertEqual(resolve_email({}, "win32")["tool"], "eml")
        self.assertFalse(resolve_email(None, "linux")["platform_override"])


if __name__ == "__main__":
    unittest.main()

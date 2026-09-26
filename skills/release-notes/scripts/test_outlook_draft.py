#!/usr/bin/env python3
"""Dependency-free tests for the macOS Outlook draft wrapper.

osascript and Outlook are replaced with fakes, so these run on every platform.
"""
from __future__ import annotations

import io
import re
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import make_outlook_draft as draft
from config import outlook_available
from make_email_draft import DraftError


def completed(returncode: int, stdout: str = "", stderr: str = ""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


class Inputs:
    """Temporary subject and body files."""

    def __enter__(self) -> tuple[Path, Path]:
        self._dir = tempfile.TemporaryDirectory()
        root = Path(self._dir.name)
        subject = root / "subject.txt"
        body = root / "body.html"
        subject.write_text("Test af release ÆØÅ\n", encoding="utf-8")
        body.write_text("<div><p>Test</p></div>", encoding="utf-8")
        return subject, body

    def __exit__(self, *exc) -> None:
        self._dir.cleanup()


def run_main(args, runner=None, which="/usr/bin/osascript", available=True):
    out, err = io.StringIO(), io.StringIO()
    runner = runner or mock.Mock(return_value=completed(0, "draft created: x\n"))
    with mock.patch.object(draft.shutil, "which", return_value=which), \
            mock.patch.object(draft, "outlook_available", return_value=available), \
            mock.patch.object(draft.subprocess, "run", runner), \
            redirect_stdout(out), redirect_stderr(err):
        code = draft.main([str(arg) for arg in args])
    return code, out.getvalue(), err.getvalue(), runner


class OutlookDraftCliTests(unittest.TestCase):
    def test_dry_run_is_the_default_and_never_runs_osascript(self) -> None:
        with Inputs() as (subject, body):
            code, out, _, runner = run_main([subject, body])
        self.assertEqual(code, 0)
        self.assertIn("dry run", out)
        runner.assert_not_called()

    def test_write_runs_the_applescript_with_absolute_paths(self) -> None:
        with Inputs() as (subject, body):
            code, out, _, runner = run_main([subject, body, "--write"])
            command = runner.call_args.args[0]
            self.assertEqual(command[:2], ["/usr/bin/osascript", str(draft.APPLESCRIPT)])
            self.assertEqual(command[2:], [str(subject.resolve()), str(body.resolve())])
        self.assertEqual(code, 0)
        self.assertIn("draft created", out)
        self.assertIn("recipients: none", out)

    def test_missing_osascript_names_the_eml_fallback(self) -> None:
        with Inputs() as (subject, body):
            code, _, err, runner = run_main([subject, body, "--write"], which=None)
        self.assertEqual(code, 2)
        self.assertIn("osascript not found", err)
        self.assertIn("make_email_draft.py", err)
        runner.assert_not_called()

    def test_missing_outlook_fails_before_scripting(self) -> None:
        with Inputs() as (subject, body):
            code, _, err, runner = run_main([subject, body], available=False)
        self.assertEqual(code, 2)
        self.assertIn("not installed", err)
        runner.assert_not_called()

    def test_permission_denied_is_explained(self) -> None:
        stderr = ("make_outlook_draft.applescript:900:1000: execution error: "
                  "outlook-draft -1743: Not authorized to send Apple events to "
                  "Microsoft Outlook. (-1743)\n")
        runner = mock.Mock(return_value=completed(1, stderr=stderr))
        with Inputs() as (subject, body), \
                mock.patch.dict(draft.os.environ, {"__CFBundleIdentifier": "com.apple.Terminal"}):
            code, _, err, _ = run_main([subject, body, "--write"], runner=runner)
        self.assertEqual(code, 2)
        self.assertIn("Privacy & Security > Automation", err)
        self.assertIn("tccutil reset AppleEvents com.apple.Terminal", err)
        self.assertIn("-1743", err)
        self.assertIn("make_email_draft.py", err)


class FailureExplanationTests(unittest.TestCase):
    def test_every_known_error_number_has_a_hint(self) -> None:
        expectations = {
            -1743: "Automation",
            -1708: "Legacy Outlook",
            -10000: "Legacy Outlook",
            -2741: "Legacy Outlook",
            -1712: "did not answer in time",
            -600: "could not be found",
            -10814: "could not be found",
        }
        for number, expected in expectations.items():
            with self.subTest(number=number):
                stderr = f"execution error: outlook-draft {number}: boom ({number})"
                self.assertEqual(draft.error_number(stderr), number)
                self.assertIn(expected, draft.explain_failure(1, stderr))

    def test_number_is_read_from_a_bare_osascript_error(self) -> None:
        self.assertEqual(draft.error_number("execution error: nope (-1712)\n"), -1712)

    def test_unknown_errors_are_passed_through_verbatim(self) -> None:
        message = draft.explain_failure(1, "execution error: odd thing (-42)")
        self.assertEqual(message, "Outlook draft failed: execution error: odd thing (-42)")
        self.assertIn("status 3", draft.explain_failure(3, ""))

    def test_open_draft_raises_on_failure(self) -> None:
        runner = mock.Mock(return_value=completed(1, stderr="outlook-draft -1712: slow"))
        with Inputs() as (subject, body), self.assertRaises(DraftError):
            draft.open_draft("/usr/bin/osascript", subject, body, runner=runner)


class AppleScriptContractTests(unittest.TestCase):
    def code_lines(self) -> str:
        text = draft.APPLESCRIPT.read_text(encoding="utf-8")
        return "\n".join(line for line in text.splitlines()
                         if not line.lstrip().startswith("--"))

    def test_script_never_sends_or_addresses_the_message(self) -> None:
        code = self.code_lines()
        self.assertNotRegex(code, re.compile(r"\bsend\b", re.IGNORECASE))
        self.assertNotRegex(code, re.compile(r"recipient", re.IGNORECASE))

    def test_script_reports_failures_and_waits_for_outlook(self) -> None:
        code = self.code_lines()
        self.assertIn("with timeout of 120 seconds", code)
        self.assertIn("on error errMsg number errNum", code)
        self.assertIn('"outlook-draft "', code)


class OutlookProbeTests(unittest.TestCase):
    def test_application_folder_is_enough(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Microsoft Outlook.app").mkdir()
            runner = mock.Mock()
            self.assertTrue(outlook_available([Path(directory)], runner=runner))
            runner.assert_not_called()

    def test_spotlight_is_consulted_when_folders_are_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch("config.shutil.which", return_value="/usr/bin/mdfind"):
            found = mock.Mock(return_value=completed(0, "/Volumes/x/Microsoft Outlook.app\n"))
            missing = mock.Mock(return_value=completed(0, ""))
            self.assertTrue(outlook_available([Path(directory)], runner=found))
            self.assertFalse(outlook_available([Path(directory)], runner=missing))

    def test_no_spotlight_means_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch("config.shutil.which", return_value=None):
            self.assertFalse(outlook_available([Path(directory)]))


if __name__ == "__main__":
    unittest.main()

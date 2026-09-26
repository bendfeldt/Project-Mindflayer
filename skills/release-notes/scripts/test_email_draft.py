#!/usr/bin/env python3
"""Dependency-free tests for cross-platform release email drafts."""
from __future__ import annotations

import subprocess
import tempfile
import unittest
from email import policy
from email.parser import BytesParser
from pathlib import Path
from unittest import mock

import make_email_draft
from config import email_tool_for_platform
from make_email_draft import (
    DraftError,
    build_draft,
    main,
    open_in_outlook,
    write_draft,
)


class EmailDraftTests(unittest.TestCase):
    def test_build_draft_is_encoded_html_with_no_recipients_and_crlf(self) -> None:
        html_body = "<div><p>Test release ÆØÅ</p></div>"

        content = build_draft("Test af release ÆØÅ", html_body)
        message = BytesParser(policy=policy.default).parsebytes(content)

        self.assertEqual(message["Subject"], "Test af release ÆØÅ")
        self.assertRegex(content, rb"Subject: [^\r\n]*=\?utf-8\?[bq]\?")
        self.assertEqual(message["X-Unsent"], "1")
        self.assertNotIn("To", message)
        self.assertNotIn("Cc", message)
        self.assertNotIn("Bcc", message)
        self.assertEqual(message.get_content_type(), "text/html")
        self.assertEqual(message.get_content_charset(), "utf-8")
        self.assertEqual(message.get_content().replace("\r\n", "\n"), html_body + "\n")
        self.assertTrue(content.endswith(b"\r\n"))
        self.assertNotIn(b"\n", content.replace(b"\r\n", b""))
        self.assertFalse(message.defects)

    def test_long_non_ascii_subject_is_folded_by_the_policy(self) -> None:
        subject = "Test af release ÆØÅ – " + "ændringer til rapporter og modeller " * 4

        content = build_draft(subject.strip(), "<p>Body</p>")
        message = BytesParser(policy=policy.default).parsebytes(content)

        self.assertEqual(message["Subject"], subject.strip())
        self.assertFalse(message.defects)

    def test_cli_is_dry_run_until_write_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subject_path = root / "subject.txt"
            body_path = root / "body.html"
            draft_path = root / "release.eml"
            subject_path.write_text("Release subject\n", encoding="utf-8")
            body_path.write_text("<p>Release body</p>", encoding="utf-8")

            self.assertEqual(
                main([str(subject_path), str(body_path), "--out", str(draft_path)]),
                0,
            )
            self.assertFalse(draft_path.exists())

            self.assertEqual(
                main(
                    [
                        str(subject_path),
                        str(body_path),
                        "--out",
                        str(draft_path),
                        "--write",
                    ]
                ),
                0,
            )
            self.assertTrue(draft_path.is_file())

    def test_existing_draft_requires_explicit_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            draft_path = Path(directory) / "release.eml"
            write_draft(draft_path, b"first", overwrite=False)

            with self.assertRaises(DraftError):
                write_draft(draft_path, b"second", overwrite=False)

            write_draft(draft_path, b"second", overwrite=True)
            self.assertEqual(draft_path.read_bytes(), b"second")

    def test_platform_routes_are_explicit(self) -> None:
        self.assertEqual(email_tool_for_platform("darwin"), "outlook-macos")
        self.assertEqual(email_tool_for_platform("win32"), "eml")
        self.assertEqual(email_tool_for_platform("linux"), "eml")


class OpenInOutlookTests(unittest.TestCase):
    """`--open` hands Outlook a temporary template and always removes it."""

    def setUp(self) -> None:
        self.content = build_draft("Release", '<p><a href="https://example.com">PR 1</a></p>')
        self.opened: list[Path] = []
        for patcher in (
            mock.patch.object(make_email_draft.time, "sleep"),
            mock.patch.object(make_email_draft.sys, "platform", "darwin"),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def record(self, argv: list[str], **_: object) -> None:
        path = Path(argv[-1])
        self.assertEqual(argv[:3], ["open", "-a", "Microsoft Outlook"])
        self.assertEqual(path.suffix, ".emltpl")
        self.assertEqual(path.read_bytes(), self.content)
        self.opened.append(path)

    def test_template_is_opened_and_removed(self) -> None:
        with mock.patch.object(make_email_draft.subprocess, "run", side_effect=self.record):
            open_in_outlook(self.content)

        self.assertEqual(len(self.opened), 1)
        self.assertFalse(self.opened[0].parent.exists())

    def test_failed_open_still_removes_the_template(self) -> None:
        def fail(argv: list[str], **kwargs: object) -> None:
            self.record(argv)
            raise subprocess.CalledProcessError(1, argv)

        with mock.patch.object(make_email_draft.subprocess, "run", side_effect=fail):
            with self.assertRaises(DraftError):
                open_in_outlook(self.content)

        self.assertFalse(self.opened[0].parent.exists())

    def test_open_is_refused_off_macos(self) -> None:
        with mock.patch.object(make_email_draft.sys, "platform", "win32"), \
                mock.patch.object(make_email_draft.subprocess, "run") as run:
            with self.assertRaises(DraftError):
                open_in_outlook(self.content)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()

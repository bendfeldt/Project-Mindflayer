#!/usr/bin/env python3
"""Dependency-free tests for cross-platform release email drafts."""
from __future__ import annotations

import tempfile
import unittest
from email import policy
from email.parser import BytesParser
from pathlib import Path

from config import email_tool_for_platform
from make_email_draft import DraftError, build_draft, main, write_draft


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


if __name__ == "__main__":
    unittest.main()

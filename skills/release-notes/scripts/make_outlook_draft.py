#!/usr/bin/env python3
"""Open an unsent Outlook for Mac draft from subject and HTML files.

The command is a dry run unless ``--write`` is supplied. It runs
make_outlook_draft.applescript, which creates the message with no recipients
and never sends it, and turns Apple Event failures into actionable messages
instead of a bare osascript error. It never falls back to another mail client
by itself; on failure it names the `.eml` route for the user to approve.

Usage:
  make_outlook_draft.py <subject.txt> <body.html>
  make_outlook_draft.py <subject.txt> <body.html> --write
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from config import outlook_available
from make_email_draft import DraftError, read_html_body, read_subject

APPLESCRIPT = Path(__file__).resolve().parent / "make_outlook_draft.applescript"

FALLBACK = ("fall-back: after approval, write a .eml draft with "
            "make_email_draft.py instead")

PERMISSION_HINT = (
    "macOS refused the Apple Event: the app running this command is not allowed "
    "to control Microsoft Outlook. Major macOS upgrades often reset this "
    "permission. Enable it under System Settings > Privacy & Security > "
    "Automation > {host} > Microsoft Outlook, or run "
    "`tccutil reset AppleEvents {host}` and retry to get the prompt again."
)
NEW_OUTLOOK_HINT = (
    "Outlook rejected the scripting command. New Outlook for Mac does not "
    "support creating drafts via AppleScript; switch to Legacy Outlook "
    "(Outlook menu > Legacy Outlook) and retry."
)
TIMEOUT_HINT = (
    "Outlook did not answer in time. It is probably still starting (first launch "
    "after an upgrade, sign-in, or a welcome sheet); finish that in Outlook and retry."
)
NOT_FOUND_HINT = "Microsoft Outlook could not be found or launched."

ERROR_HINTS = {
    -1743: PERMISSION_HINT,
    -1708: NEW_OUTLOOK_HINT,
    -10000: NEW_OUTLOOK_HINT,
    -2741: NEW_OUTLOOK_HINT,
    -1712: TIMEOUT_HINT,
    -600: NOT_FOUND_HINT,
    -10814: NOT_FOUND_HINT,
}


def error_number(stderr: str) -> int | None:
    """Extract the Apple Event error number from osascript's stderr."""
    match = re.search(r"outlook-draft (-?\d+):", stderr)
    if match is None:
        match = re.search(r"\((-\d+)\)\s*$", stderr.strip())
    return int(match.group(1)) if match else None


def explain_failure(returncode: int, stderr: str) -> str:
    """Turn a failed osascript run into a message the user can act on."""
    detail = stderr.strip() or f"osascript exited with status {returncode}"
    number = error_number(stderr)
    hint = ERROR_HINTS.get(number) if number is not None else None
    if hint is None:
        return f"Outlook draft failed: {detail}"
    host = os.environ.get("__CFBundleIdentifier", "<terminal app bundle id>")
    return f"{hint.format(host=host)}\n  osascript: {detail}"


def preflight(which=None, available=None) -> str:
    """Return the osascript path once Outlook scripting can be attempted."""
    osascript = (which or shutil.which)("osascript")
    if osascript is None:
        raise DraftError("osascript not found; the Outlook draft route needs macOS")
    if not APPLESCRIPT.is_file():
        raise DraftError(f"AppleScript helper missing: {APPLESCRIPT}")
    if not (available or outlook_available)():
        raise DraftError(NOT_FOUND_HINT + " It is not installed on this Mac.")
    return osascript


def open_draft(osascript: str, subject_file: Path, body_file: Path,
               runner=None) -> str:
    """Run the AppleScript and return its confirmation line."""
    proc = (runner or subprocess.run)(
        [osascript, str(APPLESCRIPT),
         str(subject_file.resolve()), str(body_file.resolve())],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0:
        raise DraftError(explain_failure(proc.returncode, proc.stderr or ""))
    return (proc.stdout or "").strip() or "draft created"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("subject_file", type=Path)
    parser.add_argument("body_file", type=Path)
    parser.add_argument(
        "--write",
        action="store_true",
        help="open the draft in Outlook (default: validate and print the plan only)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        subject = read_subject(args.subject_file)
        read_html_body(args.body_file)
        osascript = preflight()
        if not args.write:
            print(f"dry run: would open an unsent Outlook draft {subject!r} "
                  "(recipients: none)")
            return 0
        result = open_draft(osascript, args.subject_file, args.body_file)
    except DraftError as exc:
        print(f"error: {exc}\n{FALLBACK}", file=sys.stderr)
        return 2

    print(f"{result} (recipients: none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

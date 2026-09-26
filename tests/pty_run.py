"""Run a command in a pseudo-terminal with scripted keyboard input.

Used by the installer test suites to drive the interactive skill picker on
Linux and macOS. Usage:

    python3 tests/pty_run.py --input $'1 3\\n\\n' -- bash install.sh --project ...

The child's terminal output is written to stdout and the child's exit status
becomes this process's exit status. A child that is still running after
--timeout seconds is killed and reported as exit status 124.
"""

from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import sys
import time


def run(command: list[str], keystrokes: bytes, timeout: float) -> int:
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(command[0], command)
        finally:
            os._exit(127)

    output = bytearray()
    pending = keystrokes
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            os.close(fd)
            sys.stdout.buffer.write(bytes(output))
            sys.stdout.buffer.write(b"\n[pty_run] timed out\n")
            return 124
        writers = [fd] if pending else []
        readable, writable, _ = select.select([fd], writers, [], min(remaining, 0.2))
        if writable:
            written = os.write(fd, pending[:256])
            pending = pending[written:]
        if readable:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                # EIO: every process holding the terminal has exited.
                chunk = b""
            if not chunk:
                break
            output.extend(chunk)
    _, status = os.waitpid(pid, 0)
    os.close(fd)
    sys.stdout.buffer.write(bytes(output))
    sys.stdout.flush()
    return os.waitstatus_to_exitcode(status)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="", help="keystrokes to send; use \\n for Enter")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command[1:] if arguments.command[:1] == ["--"] else arguments.command
    if not command:
        parser.error("a command is required")
    return run(command, arguments.input.encode(), arguments.timeout)


if __name__ == "__main__":
    sys.exit(main())

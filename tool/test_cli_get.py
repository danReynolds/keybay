#!/usr/bin/env python3
"""Exercise the compiled CLI's foreground-only secret reveal path."""

from __future__ import annotations

import errno
import os
import pty
import select
import sys
import time


def read_to_eof(fd: int, timeout: float = 5.0) -> bytes:
    deadline = time.monotonic() + timeout
    output = bytearray()
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.05)
        if not readable:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                return bytes(output)
            raise
        if not chunk:
            return bytes(output)
        output.extend(chunk)
    raise AssertionError(f"foreground get did not exit: {bytes(output)!r}")


def main() -> int:
    if len(sys.argv) != 4:
        print(
            f"usage: {sys.argv[0]} KEYBAY_INTEGRATION KEY EXPECTED",
            file=sys.stderr,
        )
        return 2

    cli, key, expected = sys.argv[1:]
    pid, master = pty.fork()
    if pid == 0:
        os.execl(cli, cli, "get", key)

    output = read_to_eof(master)
    _, status = os.waitpid(pid, 0)
    os.close(master)
    exit_status = os.waitstatus_to_exitcode(status)
    if exit_status != 0:
        raise AssertionError(
            f"foreground get exited {exit_status}: {output!r}"
        )

    # A PTY maps LF to CRLF under its normal output mode.
    normalized = output.replace(b"\r\n", b"\n")
    warning = (
        b"warning: platform protection only; no additional credential is "
        b"configured.\n"
    )
    wanted = warning + expected.encode("utf-8") + b"\n"
    if normalized != wanted:
        raise AssertionError(
            f"foreground get wrote {normalized!r}, expected {wanted!r}"
        )

    print("CLI foreground get check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

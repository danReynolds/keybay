#!/usr/bin/env python3
"""Qualify controlling-TTY passphrase input while stdin remains a pipe."""

from __future__ import annotations

import errno
import fcntl
import os
import pty
import select
import subprocess
import sys
import termios
import time


def read_until(fd: int, needle: bytes, timeout: float = 5.0) -> bytes:
    deadline = time.monotonic() + timeout
    output = bytearray()
    while needle not in output and time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.05)
        if not readable:
            continue
        output.extend(os.read(fd, 4096))
    if needle not in output:
        raise AssertionError(f"terminal omitted {needle!r}: {bytes(output)!r}")
    return bytes(output)


def read_available(fd: int) -> bytes:
    output = bytearray()
    while True:
        readable, _, _ = select.select([fd], [], [], 0)
        if not readable:
            return bytes(output)
        try:
            chunk = os.read(fd, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                return bytes(output)
            raise
        if not chunk:
            return bytes(output)
        output.extend(chunk)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} HARNESS", file=sys.stderr)
        return 2

    harness = os.path.abspath(sys.argv[1])
    stdin_read, stdin_write = os.pipe()
    stdout_read, stdout_write = os.pipe()
    master, slave = pty.openpty()
    initial_flags = termios.tcgetattr(slave)[3]

    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.close(stdin_write)
        os.close(stdout_read)
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        os.dup2(stdin_read, 0)
        os.dup2(stdout_write, 1)
        os.dup2(stdout_write, 2)
        os.close(stdin_read)
        os.close(stdout_write)
        os.close(slave)
        os.execl(harness, harness)

    os.close(stdin_read)
    os.close(stdout_write)
    try:
        terminal_output = read_until(master, b"Keybay passphrase: ")
    except AssertionError as error:
        _, status = os.waitpid(pid, 0)
        diagnostic = os.read(stdout_read, 4096)
        raise AssertionError(
            f"{error}; child={os.waitstatus_to_exitcode(status)} {diagnostic!r}"
        ) from error
    passphrase = "päss word".encode("utf-8")
    os.write(master, passphrase + b"\n")
    stdin_payload = b"child-stdin-must-survive"
    os.write(stdin_write, stdin_payload)
    os.close(stdin_write)

    expected = (
        f"passphrase-bytes:{len(passphrase)}\n"
        f"stdin-bytes:{len(stdin_payload)}\n"
    ).encode("utf-8")
    output = bytearray(read_until(stdout_read, expected))
    restored_flags = termios.tcgetattr(slave)[3]
    if bool(initial_flags & termios.ECHO) != bool(restored_flags & termios.ECHO):
        raise AssertionError("terminal echo mode was not restored")

    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        readable, _, _ = select.select([stdout_read], [], [], 0.05)
        if not readable:
            continue
        chunk = os.read(stdout_read, 4096)
        if not chunk:
            break
        output.extend(chunk)
    else:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        raise AssertionError(
            f"prompt harness did not exit; stdout={bytes(output)!r} "
            f"terminal={terminal_output!r}"
        )
    os.close(stdout_read)
    # Drain the controlling terminal before waiting. Darwin may keep a session
    # leader in exit while its final terminal output is still queued.
    terminal_output += read_available(master)
    wait_deadline = time.monotonic() + 2.0
    status = None
    while time.monotonic() < wait_deadline:
        waited, candidate = os.waitpid(pid, os.WNOHANG | os.WUNTRACED)
        if waited == pid:
            status = candidate
            break
        time.sleep(0.02)
    if status is None:
        process_state = subprocess.run(
            ["/bin/ps", "-o", "pid=,ppid=,stat=,wchan=,command=", "-p", str(pid)],
            check=False,
            capture_output=True,
            text=True,
        ).stdout.strip()
        os.kill(pid, 9)
        kill_deadline = time.monotonic() + 2.0
        while time.monotonic() < kill_deadline:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                break
            time.sleep(0.02)
        raise AssertionError(
            f"prompt harness closed output but did not exit: {bytes(output)!r}; "
            f"terminal={terminal_output!r}; process={process_state!r}"
        )
    if os.WIFSTOPPED(status):
        stopped_by = os.WSTOPSIG(status)
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        raise AssertionError(f"prompt harness stopped by signal {stopped_by}")

    terminal_output += read_available(master)

    if os.waitstatus_to_exitcode(status) != 0:
        raise AssertionError(f"prompt harness failed: {bytes(output)!r}")
    if passphrase in terminal_output:
        raise AssertionError("controlling terminal echoed the passphrase")
    if bytes(output) != expected:
        raise AssertionError(f"output {bytes(output)!r}, expected {expected!r}")
    os.close(master)
    os.close(slave)

    unattended = subprocess.run(
        [harness],
        input=b"must-not-be-a-passphrase",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if unattended.returncode != 4:
        raise AssertionError(
            f"unattended prompt exited {unattended.returncode}: {unattended.stderr!r}"
        )

    print("CLI controlling-terminal passphrase check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

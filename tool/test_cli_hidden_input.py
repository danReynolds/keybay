#!/usr/bin/env python3
"""Hidden prompt boundaries with a surviving synthetic shell, never a vault."""
import errno
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time


def check(executable, payload, expected_status=0, expected=None,
          passphrase=False, echo=True, arguments=(), signal_number=None):
    pid, master = pty.fork()
    if pid == 0:
        attributes = termios.tcgetattr(0)
        attributes[3] = (attributes[3] | termios.ECHO if echo
                         else attributes[3] & ~termios.ECHO)
        termios.tcsetattr(0, termios.TCSANOW, attributes)
        before = termios.tcgetattr(0)
        worker = subprocess.Popen([executable, *arguments],
                                  stdin=subprocess.DEVNULL if passphrase else None)
        print(f'worker:{worker.pid}', flush=True)
        status = worker.wait()
        after = termios.tcgetattr(0)
        # Darwin sets PENDIN when canonical input resumes. This is transient
        # kernel state, not a caller setting; compare every configured mode.
        pending_input = getattr(termios, 'PENDIN', 0)
        before[3] &= ~pending_input
        after[3] &= ~pending_input
        restored = after == before
        if not restored:
            print(f'terminal changed: before={before!r}, after={after!r}', flush=True)
        print(f'\nshell:status={status},restored={restored}', flush=True)
        os._exit(0)
    output = bytearray()
    pending = b''
    sent = False
    reaped = False
    os.set_blocking(master, False)
    deadline = time.monotonic() + 8
    try:
        while time.monotonic() < deadline:
            readable, writable, _ = select.select(
                [master], [master] if pending else [], [], .01)
            if readable:
                try:
                    chunk = os.read(master, 16384)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                output.extend(chunk)
            if not sent and (b'(input hidden): ' in output or
                             b'Keybay passphrase: ' in output):
                pending = payload
                sent = True
                if signal_number is not None:
                    worker = int(re.search(rb'worker:(\d+)', output)[1])
                    os.kill(worker, signal_number)
            if writable and pending:
                pending = pending[os.write(master, pending[:4096]):]
            if b'shell:status=' in output:
                break
        marker = f'shell:status={expected_status},restored=True'.encode()
        assert marker in output, f'prompt did not restore/finish: {bytes(output)!r}'
        assert not pending, 'prompt exited before the test input was delivered'
        if expected:
            assert expected in output, f'missing expected result: {bytes(output)!r}'
        assert b'x' * 32 not in output and b'probe\r\n' not in output, 'secret echoed'
        os.waitpid(pid, 0)
        reaped = True
    finally:
        if not reaped:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == 0:
                try:
                    os.killpg(pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    # Darwin may have already detached a session leader that
                    # is finishing exit. Reap it without masking the failure.
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                os.waitpid(pid, 0)
        os.close(master)


def main():
    value, phrase = map(os.path.abspath, sys.argv[1:])
    for echo in (True, False):
        check(value, b'\x04', expected_status=2, echo=echo)
        check(value, b'x' * 32 + b'\x04', expected=b'read:32', echo=echo)
        check(value, b'partial\x03', expected_status=130, echo=echo)
        check(phrase, b'\x04', expected_status=2, passphrase=True, echo=echo)
    for length in (1023, 1024, 8192, 1048576):
        check(value, b'x' * length + b'\r', expected=f'read:{length}'.encode())
    check(value, b'x' * 1048577 + b'\r', expected_status=2)
    for length in (1023, 1024):
        check(phrase, b'x' * length + b'\r', passphrase=True,
              expected=f'passphrase-bytes:{length}'.encode())
    check(phrase, b'x' * 1025 + b'\r', expected_status=2, passphrase=True)
    for count, status in ((512, 0), (513, 2)):
        check(phrase, ('é' * count + '\r').encode(), expected_status=status,
              passphrase=True)
    paste = b'\x1b[200~' + 'probe\r\n🔑\x03\t\x1b[31m\r\n'.encode() + b'\x1b[201~\r'
    for executable, passphrase in ((value, False), (phrase, True)):
        check(executable, paste, passphrase=passphrase,
              arguments=('--verify-paste',), expected=b'paste:exact')
    # Overflow remains rejected even when an editing key follows it; a fresh
    # Ctrl+U draft is the explicit recovery path.
    check(phrase, b'x' * 1025 + b'\x7f\r', expected_status=2, passphrase=True)
    check(phrase, b'x' * 1025 + b'\x15ok\r', expected=b'passphrase-bytes:2', passphrase=True)
    print('Hidden input: 22 native boundary, exact paste and mode-restoration cases passed')


if __name__ == '__main__':
    main()

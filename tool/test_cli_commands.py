#!/usr/bin/env python3
"""Real command/SDK/terminal flows over disposable provider/file boundaries."""
from __future__ import annotations
import errno
import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


class Invocation:
    def __init__(self, cli, args, *, pipe_input=None, capture=False, second_tty=False):
        self.output = bytearray()
        self.capture = bytearray()
        self.read_fd = None
        input_fds = os.pipe() if pipe_input is not None else None
        output_fds = os.pipe() if capture else None
        other = pty.openpty() if second_tty else None
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            if input_fds:
                os.close(input_fds[1])
                os.dup2(input_fds[0], 0)
                os.close(input_fds[0])
            if output_fds:
                os.close(output_fds[0])
                os.dup2(output_fds[1], 1)
                os.close(output_fds[1])
            if other:
                os.close(other[0])
                os.dup2(other[1], 1)
                os.close(other[1])
            os.execv(cli, [cli, *args])
        if input_fds:
            os.close(input_fds[0])
            os.write(input_fds[1], pipe_input)
            os.close(input_fds[1])
        if output_fds:
            os.close(output_fds[1])
            self.read_fd = output_fds[0]
        if other:
            os.close(other[1])
            self.read_fd = other[0]
        self.status = None

    def receive(self, needle=None, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if needle is not None and needle in self.output:
                return bytes(self.output)
            fds = [self.master] + ([self.read_fd] if self.read_fd is not None else [])
            ready, _, _ = select.select(fds, [], [], .02)
            eof = False
            for fd in ready:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b''
                if fd == self.master:
                    self.output.extend(data)
                    eof = not data
                else:
                    self.capture.extend(data)
            waited, status = os.waitpid(self.pid, os.WNOHANG) if self.status is None else (0, 0)
            if waited:
                self.status = os.waitstatus_to_exitcode(status)
            if eof and self.status is not None:
                if needle is not None and needle not in self.output:
                    raise AssertionError(f'missing {needle!r}: {bytes(self.output)!r}')
                return bytes(self.output)
        raise AssertionError(f'command timeout: {bytes(self.output)!r}')

    def authenticate(self, phrase=b'disposable-passphrase'):
        self.receive(b'Keybay passphrase: ')
        assert not termios.tcgetattr(self.master)[3] & termios.ECHO
        os.write(self.master, phrase + b'\n')

    def finish(self, status):
        self.receive(b'test:closed')
        assert termios.tcgetattr(self.master)[3] & termios.ECHO, 'echo was not restored'
        self.receive()
        assert self.status == status, (self.status, status, bytes(self.output))
        assert b'disposable-passphrase' not in self.output, 'passphrase echoed'

    def close(self):
        if self.status is None:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.master)
        if self.read_fd is not None:
            os.close(self.read_fd)


def main():
    cli = os.path.abspath(sys.argv[1])
    real = len(sys.argv) > 2 and sys.argv[2] == '--real-provider'
    prefix = ['--test-command'] if real else []
    def check(args, action, **kwargs):
        invocation = Invocation(cli, [*prefix, *args], **kwargs)
        try:
            action(invocation)
        finally:
            invocation.close()

    def protected_list(p):
        p.receive(b'Keybay passphrase: ')
        assert b'acme/key' not in p.output
        p.authenticate()
        p.finish(0)
        assert b'acme/key' in p.output
    check(['list'], protected_list)

    def wrong(p):
        p.authenticate(b'wrong')
        p.finish(1)
        assert p.output.count(b'Keybay passphrase: ') == 1
        assert b'acme/key' not in p.output
    check(['list'], wrong)

    def get(p):
        p.authenticate()
        p.finish(0)
        assert b'disposable-value' in p.output
    check(['get', 'acme/key'], get, pipe_input=b'stdin-is-not-authentication')

    def refused(p):
        p.finish(4)
        assert b'Keybay passphrase' not in p.output
        assert b'disposable-value' not in p.output + p.capture
    check(['get', 'acme/key'], refused, capture=True)
    check(['get', 'acme/key'], refused, second_tty=True)
    check(['set', 'acme/key'], refused, pipe_input=b'not-interactive')

    def tty_stdin(p):
        p.finish(2)
        assert b'Keybay passphrase' not in p.output
    check(['set', '--stdin', 'acme/key'], tty_stdin)

    def interactive_set(p):
        p.authenticate()
        p.receive(b'Value for acme/key (input hidden): ')
        assert not termios.tcgetattr(p.master)[3] & termios.ECHO
        os.write(p.master, b'disposable-value\n')
        p.finish(0)
        assert b'Stored acme/key' in p.output
        assert b'disposable-value' not in p.output
    check(['set', 'acme/key'], interactive_set)

    def cancel_value(p):
        p.authenticate()
        p.receive(b'Value for acme/key (input hidden): ')
        os.kill(p.pid, signal.SIGINT)
        p.finish(130)
        assert b'Stored acme/key' not in p.output
    check(['set', 'acme/key'], cancel_value)

    def piped_set(p):
        p.authenticate()
        p.finish(0)
        assert b'Stored acme/key' in p.output
        assert b'disposable-value' not in p.output
    check(['set', '--stdin', 'acme/key'], piped_set, pipe_input=b'disposable-value\n')

    def cancelled(p):
        p.receive(b'Keybay passphrase: ')
        os.kill(p.pid, signal.SIGINT)
        p.finish(130)
        assert b'acme/key' not in p.output
    check(['list'], cancelled)

    def late_open(p):
        p.receive(b'test:opening')
        os.kill(p.pid, signal.SIGTERM)
        p.finish(143)
        assert b'acme/key' not in p.output
    if not real:
        check(['--platform-only', '--delay-open', 'list'], late_open)

    # run replaces the harness, so no test:closed marker is expected. Its
    # summary belongs exclusively to the controlling terminal, and the child
    # inherits untouched stdin with exactly the selected overlay.
    with tempfile.TemporaryDirectory(prefix='keybay-command-') as directory:
        manifest = Path(directory) / 'manifest.env'
        manifest.write_text('TOKEN=kb://acme/key\nPATH=/literal-secret\n')
        probe = 'import os,sys;print(os.environ["TOKEN"]);print(sys.stdin.read())'
        p = Invocation(cli, [*prefix, 'run', '-f', str(manifest), '--', sys.executable, '-c', probe],
                       pipe_input=b'child-stdin', capture=True)
        try:
            p.receive(b'Keybay passphrase: ')
            assert b'TOKEN <- acme/key' in p.output
            assert b'PATH (literal) [affects execution]' in p.output
            assert b'/literal-secret' not in p.output
            assert b'disposable-value' not in p.output
            p.authenticate()
            p.receive()
            assert p.status == 0, bytes(p.output)
            assert p.capture == b'disposable-value\nchild-stdin\n', bytes(p.capture)
        finally:
            p.close()

    def remove(p):
        p.authenticate()
        p.finish(0)
        assert b'disposable-value' not in p.output
    check(['rm', 'acme/key'], remove)
    check(['rm', 'acme/key'], remove)  # Idempotent on the real persistent fixture.

    result = subprocess.run([cli, *prefix, 'list'], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True, timeout=10)
    assert result.returncode == 4, result
    assert b'acme/key' not in result.stdout + result.stderr
    print('CLI command lifecycle and controlling-terminal checks passed')


if __name__ == '__main__':
    main()

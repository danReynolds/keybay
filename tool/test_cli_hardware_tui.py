#!/usr/bin/env python3
"""Unattended hardware TUI lifecycle; fake provider, real SDK and POSIX TTY."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import re
import select
import shlex
import signal
import struct
import sys
import tempfile
import termios
import time

from test_cli_commands import Invocation

PIN = b'pty-pin-8642'


def main():
    cli = os.path.abspath(sys.argv[1])
    passed = 0

    def check(scenario, action, *, size=(24, 80), idle=False):
        nonlocal passed
        with tempfile.TemporaryDirectory(prefix='keybay-hardware-pty-') as directory:
            receipt = Path(directory) / 'receipt.json'
            p = Invocation(cli, [scenario, str(receipt), *(['--idle'] if idle else [])])
            p.history = bytearray()
            p.receipt = receipt
            p.scenario = scenario
            fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', *size, 0, 0))
            try:
                action(p)
                data = events(p)
                final = data[-1]
                assert final['event'] == 'finished', data
                assert final['sessionsClosed'], data
                assert final['inputsCleared'], data
                assert final['providerReleased'], data
                output = bytes(p.history + p.output)
                # Styling/caret escapes must not conceal a plaintext leak from
                # the check when a full frame is repainted after resizing.
                plain = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', output)
                assert PIN not in plain, 'PIN appeared in native terminal output'
                assert b'disposable-value' not in plain, 'value appeared without Reveal'
                assert b'\x1b[?1049l' in output, 'alternate screen not restored'
                passed += 1
                print(f'PASS {scenario}: {action.__name__} {size}', flush=True)
            finally:
                p.close()

    def events(p):
        return json.loads(p.receipt.read_text()) if p.receipt.exists() else []

    def wait_event(p, event, count=1):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            found = [item for item in events(p) if item['event'] == event]
            if len(found) >= count:
                return found[-1]
            ready, _, _ = select.select([p.master], [], [], .02)
            if ready:
                try:
                    p.output.extend(os.read(p.master, 65536))
                except OSError:
                    break
        raise AssertionError(f'missing {event}: {events(p)!r}; {bytes(p.output)!r}')

    def fresh(p):
        p.history.extend(p.output)
        p.output.clear()

    def begin(p):
        if p.scenario.startswith('unlock-'):
            p.receive(b'Choose an unlock method')
            os.write(p.master, b'\r')
            p.receive(b'Unlock with hardware key')
        else:
            p.receive(b'acme/key')
            os.write(p.master, b's')
            p.receive(b'Security')
            os.write(p.master, b'h')
            p.receive(b'Name (optional)')
        fresh(p)
        os.write(p.master, b'\r')
        wait_event(p, 'attempt')

    def success(p, count):
        if p.scenario.startswith('enroll-'):
            p.receive(b'Hardware key added.')
            fresh(p)
            os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b'q')
        p.finish(0)
        final = events(p)[-1]
        assert final['attempts'] == count, final
        assert final['generationChanged'], final
        assert final['capturedInputs'] > 0 or p.scenario.endswith('-wait'), final

    def pin_resize(p):
        begin(p)
        p.receive(b'Enter the existing PIN')
        assert not termios.tcgetattr(p.master)[3] & termios.ECHO
        # Bracketed paste is one native event, followed by blur and two resizes.
        os.write(p.master, b'\x1b[200~' + PIN + b'\x1b[201~')
        # SIGWINCH and terminal bytes are independent queues on Linux. Wait
        # until the paste was accepted before testing draft preservation.
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            plain = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', bytes(p.output))
            if ('•' * len(PIN)).encode() in plain: break
            if select.select([p.master], [], [], .02)[0]:
                p.output.extend(os.read(p.master, 65536))
        else:
            raise AssertionError('PIN paste was not painted before resize')
        os.write(p.master, b'\x1b[O')
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 30, 0, 0))
        p.receive(b'Draft kept hidden.')
        fresh(p)
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        p.receive(b'Enter the existing PIN')
        os.write(p.master, b'\x1b[I\r')
        success(p, 2)

    def rejected_pin(p):
        begin(p)
        p.receive(b'Enter the existing PIN')
        os.write(p.master, PIN + b'\r')
        p.receive(b'That PIN was rejected.')
        fresh(p)
        os.write(p.master, b'\r')  # Submit the cleared field without fresh input.
        p.receive(b'Enter the existing PIN')
        assert len([e for e in events(p) if e['event'] == 'attempt']) == 2
        fresh(p)
        os.write(p.master, PIN + b'\r')
        success(p, 3)

    def blocked_pin(p):
        begin(p)
        p.receive(b'Enter the existing PIN')
        os.write(p.master, PIN + b'\r')
        p.receive(b'The hardware PIN is blocked.')
        os.write(p.master, b'\r\r\x03')
        p.finish(130)
        final = events(p)[-1]
        assert final['attempts'] == 2, final
        assert not final['generationChanged'], final

    def cancel_retry(p):
        begin(p)
        fresh(p)
        os.write(p.master, b'\x1b')
        wait_event(p, 'cancelled')
        # The operation deliberately keeps running briefly after cancellation.
        # Enter cannot launch a second attempt during that interval.
        os.write(p.master, b'\r\r')
        wait_event(p, 'drained')
        if p.scenario.startswith('enroll-'):
            p.receive(b'Security')
            os.write(p.master, b'h')
            p.receive(b'Name (optional)')
        else:
            p.receive(b'Choose an unlock method')
            os.write(p.master, b'\r')
            p.receive(b'Unlock with hardware key')
        assert len([e for e in events(p) if e['event'] == 'attempt']) == 1
        fresh(p)
        os.write(p.master, b'\r')
        success(p, 2)

    def terminate_wait(p):
        begin(p)
        os.kill(p.pid, signal.SIGTERM)
        p.finish(143)
        data = events(p)
        assert [e['event'] for e in data][-3:] == ['cancelled', 'drained', 'finished'], data
        assert data[-1]['attempts'] == 1, data
        assert not data[-1]['generationChanged'], data

    def interrupt_pin(p):
        begin(p)
        p.receive(b'Enter the existing PIN')
        os.write(p.master, PIN + b'\x03')
        p.finish(130)
        final = events(p)[-1]
        assert final['attempts'] == 1, final
        assert not final['generationChanged'], final

    def idle_wait(p):
        begin(p)
        p.finish(0)
        data = events(p)
        assert [e['event'] for e in data][-3:] == ['cancelled', 'drained', 'finished'], data
        assert not data[-1]['generationChanged'], data

    for mode in ('enroll', 'unlock'):
        for size in ((24, 40), (20, 80)):
            check(f'{mode}-pin', pin_resize, size=size)
        check(f'{mode}-reject', rejected_pin)
        check(f'{mode}-blocked', blocked_pin)
        check(f'{mode}-wait', cancel_retry)
        check(f'{mode}-wait', terminate_wait)
        check(f'{mode}-pin', interrupt_pin)
        check(f'{mode}-wait', idle_wait, idle=True)

    # An interactive shell can reclaim its terminal while the TUI is stopped.
    # Resume the TUI in the background and require cancellation before cleanup.
    # All processes and terminals here belong to this disposable test session.
    for mode in ('enroll', 'unlock'):
        with tempfile.TemporaryDirectory(prefix='keybay-hardware-foreground-') as directory:
            p = Invocation('/bin/bash', ['--norc', '--noprofile', '-i'])
            p.history = bytearray()
            p.receipt = Path(directory) / 'receipt.json'
            p.scenario = f'{mode}-wait'
            fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            tui_pid = None
            try:
                p.receive(b'# ' if os.geteuid() == 0 else b'$ ')
                command = shlex.join([cli, p.scenario, str(p.receipt)])
                os.write(p.master, ("PS1='KB''-HW$ '; set -m; " + command + '\n').encode())
                tui_pid = wait_event(p, 'ready')['pid']
                begin(p)
                fresh(p)
                os.kill(tui_pid, signal.SIGSTOP)
                p.receive(b'KB-HW$ ')
                fresh(p)
                os.write(p.master, b'bg %1\n')
                final = wait_event(p, 'finished')
                assert final['exitCode'] == 1, final
                assert final['attempts'] == 1, final
                assert final['sessionsClosed'] and final['inputsCleared'], final
                assert final['providerReleased'], final
                assert not final['generationChanged'], final
                assert [e['event'] for e in events(p)][-3:] == ['cancelled', 'drained', 'finished']
                p.receive(b'test:closed')
                assert b'acme/key' not in p.output, 'background TUI repainted records'
                assert b'disposable-value' not in p.history + p.output
                os.write(p.master, b'wait %1; exit 0\n')
                p.receive()
                assert p.status == 0, p.status
                passed += 1
                print(f'PASS {p.scenario}: foreground_loss', flush=True)
            finally:
                if tui_pid is not None and p.status is None:
                    try:
                        os.kill(tui_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                p.close()
    print(f'Hardware TUI PTY regression: {passed} passed (simulated provider, no physical key).')


if __name__ == '__main__':
    main()

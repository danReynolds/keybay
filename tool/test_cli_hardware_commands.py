#!/usr/bin/env python3
"""Hardware command authentication with fake providers and real controlling TTYs."""
import json
import os
from pathlib import Path
import signal
import re
import subprocess
import sys
import tempfile
from test_cli_commands import Invocation

PIN = b'command-pin-2468'


def main():
    cli = os.path.abspath(sys.argv[1])
    passed = 0
    with tempfile.TemporaryDirectory(prefix='keybay-hardware-commands-') as directory:
        base = Path(directory)
        def run(command, action, scenario='unlock-pin', options=(), **kwargs):
            nonlocal passed
            receipt = base / f'{passed}.json'
            p = Invocation(cli, [scenario, str(receipt), *options, '--command', *command], **kwargs)
            try:
                action(p)
                assert PIN not in p.output + p.capture
                data = json.loads(receipt.read_text())
                if command[0] != 'run':
                    final = data[-1]
                    assert final['event'] == 'finished', data
                    assert final['sessionsClosed'] and final['inputsCleared'], final
                    assert final['providerReleased'], final
                passed += 1
                print(f'PASS {scenario}: {command[0]} / {action.__name__}', flush=True)
            finally:
                p.close()
        def pin(p):
            p.receive(b'Hardware key PIN (existing PIN, input hidden): ')
            os.write(p.master, PIN + b'\n')
        def listing(p):
            pin(p); p.finish(0)
            assert p.capture == b'acme/key\n', p.capture
        run(['list'], listing, capture=True)
        def get(p):
            pin(p); p.finish(0)
            assert b'disposable-value' in p.output
        run(['get', 'acme/key'], get)
        def piped_set(p):
            pin(p); p.finish(0)
            assert b'Stored acme/key' in p.output
            assert b'piped-secret' not in p.output + p.capture
        run(['set', '--stdin', 'acme/key'], piped_set, pipe_input=b'piped-secret\n', capture=True)
        def interactive_set(p):
            pin(p); p.receive(b'Value for acme/key (input hidden): ')
            os.write(p.master, b'interactive-secret\n'); p.finish(0)
            assert b'interactive-secret' not in p.output
        run(['set', 'acme/key'], interactive_set)
        def remove(p):
            pin(p); p.finish(0)
            assert b'disposable-value' not in p.output
        run(['rm', 'acme/key'], remove)
        def choose(p):
            p.receive(b'Method number: ')
            assert b'Backup hardware key' in p.output
            number = re.search(rb'(\d+)\. "Backup hardware key"', p.output)[1]
            os.write(p.master, number + b'\n')
            pin(p); p.finish(0)
            assert p.capture == b'acme/key\n'
        run(['list'], choose, options=['--two-methods'], capture=True)
        def phrase(p):
            p.receive(b'Method number: ')
            number = re.search(rb'(\d+)\. "Passphrase"', p.output)[1]
            os.write(p.master, number + b'\n'); p.authenticate(); p.finish(0)
            assert b'Hardware key PIN' not in p.output
        run(['list'], phrase, options=['--with-passphrase'])
        def wrong(p):
            pin(p); p.finish(1)
            assert p.output.count(b'Hardware key PIN') == 1
            assert b'That PIN was rejected' in p.output
            assert b'acme/key' not in p.output
        run(['list'], wrong, scenario='unlock-reject')
        def cancel(p):
            p.receive(b'Ctrl+C cancels.')
            os.write(p.master, b'\x03'); p.finish(130)
            assert b'acme/key' not in p.output
        run(['list'], cancel, scenario='unlock-wait')
        def terminate(p):
            p.receive(b'Ctrl+C cancels.')
            os.kill(p.pid, signal.SIGTERM); p.finish(143)
            assert b'acme/key' not in p.output
        run(['list'], terminate, scenario='unlock-wait')
        def redirected_get(p):
            p.finish(4)
            assert b'Hardware key' not in p.output
        run(['get', 'acme/key'], redirected_get, capture=True)
        manifest = base / 'manifest.env'
        manifest.write_text('TOKEN=kb://acme/key\n')
        child = 'import os,sys;print(os.environ["TOKEN"]);print(sys.stdin.read())'
        def launch(p):
            pin(p)
            assert b'TOKEN <- acme/key' in p.output
            p.receive()
            assert p.status == 0, p.status
            assert p.capture == b'disposable-value\nchild-input\n', p.capture
            assert b'disposable-value' not in p.output
        run(['run', '-f', str(manifest), '--', sys.executable, '-c', child], launch,
            capture=True, pipe_input=b'child-input')
        unattended = subprocess.run([cli, 'unlock-pin', str(base/'unattended.json'), '--command', 'list'],
            input=b'never-a-pin', capture_output=True, start_new_session=True)
        assert unattended.returncode == 4, unattended.stderr
        assert b'acme/key' not in unattended.stdout
        assert not any(e['event'] == 'attempt' for e in json.loads((base/'unattended.json').read_text()))
        passed += 1
    print(f'Hardware command PTY regression: {passed} passed (simulated provider).')


if __name__ == '__main__':
    main()

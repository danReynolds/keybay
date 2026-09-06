"""Real GNOME prompt on a private Xvfb display and disposable account only."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    work, app, peer = sys.argv[1:]
    receipt_path = Path(work) / 'receipt.json'
    receipt = json.loads(receipt_path.read_text())
    active = []
    stage = 'lock'
    observations = {}

    def command(*args, timeout=15):
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            raise ValueError('command_failed')
        return result.stdout.strip()

    def locked():
        return command('gdbus', 'call', '--session', '--dest', 'org.freedesktop.secrets',
            '--object-path', '/org/freedesktop/secrets/collection/login', '--method',
            'org.freedesktop.DBus.Properties.Get', 'org.freedesktop.Secret.Collection', 'Locked') == '(<true>,)'

    def lock():
        command('gdbus', 'call', '--session', '--dest', 'org.freedesktop.secrets',
            '--object-path', '/org/freedesktop/secrets', '--method',
            'org.freedesktop.Secret.Service.Lock', "[objectpath '/org/freedesktop/secrets/collection/login']")
        if not locked():
            raise ValueError('collection_not_locked')

    def launch(mode, identity=None):
        p = subprocess.Popen(['flatpak', 'run', '--user', identity or app, mode], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        active.append(p)
        return p

    def prompt(processes=None):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if processes and all(p.poll() is not None for p in processes):
                return None
            result = subprocess.run(['xdotool', 'search', '--onlyvisible', '--class', 'gcr-prompter'], capture_output=True, text=True)
            windows = result.stdout.split()
            if result.returncode == 0 and len(windows) == 1:
                # No external window manager or personal desktop is present.
                command('xdotool', 'windowfocus', '--sync', windows[0])
                return windows[0]
            time.sleep(0.1)
        raise ValueError('real_prompt_not_observed')

    def finish(p, expected=None):
        try:
            output, _ = p.communicate(timeout=70)
        except subprocess.TimeoutExpired as error:
            observations[stage + '_process_timed_out'] = True
            try:
                value = json.loads(error.stdout or '')
                if isinstance(value, dict) and set(value).issubset({'opened', 'code'}):
                    observations[stage + '_receipt_before_timeout'] = value
            except (ValueError, TypeError):
                pass
            raise
        active.remove(p)
        if p.returncode != 0:
            raise ValueError('harness_failed')
        if expected is not None and output.strip() != expected:
            raise ValueError('unexpected_result')
        return output.strip()

    try:
        lock()
        stage = 'user-cancel'
        p = launch('prompt-open')
        prompt()
        observations['user_cancel_prompt_observed'] = True
        command('xdotool', 'key', 'Escape')
        response = json.loads(finish(p))
        if response not in [{'opened': False, 'code': 'platformInteractionRequired'},
                            {'opened': False, 'code': 'platformOperationFailed'}] or not locked():
            raise ValueError('cancel_did_not_fail_closed')
        observations['user_cancel_failure_code'] = response['code']
        stage = 'user-cancel-recovery'
        p = launch('prompt-open')
        prompt()
        command('xdotool', 'type', '--clearmodifiers', '--', 'keybay-disposable-ci-password')
        command('xdotool', 'key', 'Return')
        if json.loads(finish(p)) != {'opened': True} or locked():
            raise ValueError('cancel_recovery_failed')
        observations['user_cancel_recovery_without_restart'] = True

        stage = 'timeout'
        lock()
        p = launch('prompt-timeout')
        prompt()
        observations['timeout_prompt_observed'] = True
        finish(p, 'ok')
        observations['prompted_timeout_failed_closed'] = True
        # Dismiss any native dialog still present after Request.Close. Observe
        # recovery separately; never label this as provider-cancelled UI.
        command('xdotool', 'key', 'Escape')
        stage = 'timeout-recovery'
        p = launch('prompt-open')
        prompt()
        command('xdotool', 'type', '--clearmodifiers', '--', 'keybay-disposable-ci-password')
        command('xdotool', 'key', 'Return')
        if json.loads(finish(p)) != {'opened': True} or locked():
            raise ValueError('timeout_recovery_failed')
        observations['timeout_recovery_without_restart'] = True

        stage = 'concurrent-cancel'
        lock()
        pending = [launch('prompt-open', identity) for identity in (app, peer)]
        prompt_count = 0
        for _ in range(2):
            if prompt(pending) is None:
                break
            prompt_count += 1
            command('xdotool', 'key', 'Escape')
            time.sleep(0.2)
        if prompt_count == 0:
            raise ValueError('concurrent_prompt_not_observed')
        for p in pending:
            if json.loads(finish(p)) not in [{'opened': False, 'code': 'platformInteractionRequired'},
                                            {'opened': False, 'code': 'platformOperationFailed'}]:
                raise ValueError('concurrent_cancel_did_not_fail_closed')
        observations['concurrent_prompts_observed'] = prompt_count
        stage = 'concurrent-cancel-recovery'
        p = launch('prompt-open')
        prompt()
        command('xdotool', 'type', '--clearmodifiers', '--', 'keybay-disposable-ci-password')
        command('xdotool', 'key', 'Return')
        if json.loads(finish(p)) != {'opened': True} or locked():
            raise ValueError('concurrent_cancel_recovery_failed')
        if json.loads(finish(launch('prompt-open', peer))) != {'opened': True}:
            raise ValueError('peer_cancel_recovery_failed')
        observations['concurrent_cancel_both_stores_recovered_without_restart'] = True
        receipt['prompted_cancellation_recovery'] = True
        print('PASS: real GNOME prompt cancellation, timeout and existing-store recovery')
    except (ValueError, OSError, subprocess.SubprocessError):
        receipt['prompted_cancellation_recovery'] = False
        receipt['prompt_failure_stage'] = stage
        print('FAIL: real GNOME prompt check at ' + stage)
    finally:
        receipt['prompt_observations'] = observations
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        for process in active:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)


if __name__ == '__main__':
    main()

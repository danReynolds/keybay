"""Dedicated SDK fixture; never signs the product or publishes an artifact."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile

from lifecycle import require


def verify_artifacts(seed, reopen):
    require(seed['build'] == '101' and reopen['build'] == '102', 'wrong_builds')
    require(seed['sha256'] != reopen['sha256'] and seed['cdhash'] != reopen['cdhash'], 'same_binary')
    for field in ('identifier', 'team', 'requirement', 'runtime'):
        require(seed[field] == reopen[field], 'signing_identity_changed')


def verify_receipt(value, nonce, subject, build, phase, pid):
    require(value == {'kind': 'keybay-macos-developer-id', 'nonce': nonce,
        'subject': subject, 'build': build, 'phase': phase, 'pid': pid, 'status': 'pass'}, 'invalid_receipt')


def main():
    os.umask(0o077)
    repo = Path(__file__).resolve().parents[2]
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()
    require(not git('status', '--porcelain', '--untracked-files=all'), 'dirty_source')
    subject = 'git-commit:' + git('rev-parse', 'HEAD')
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    matches = re.findall(r'\b([0-9A-F]{40}) "Developer ID Application:[^"\n]+ \(([A-Z0-9]{10})\)"', identities)
    requested = os.environ.get('KEYBAY_APPLE_TEAM_ID')
    matches = [m for m in matches if not requested or m[1] == requested]
    if len(matches) != 1:
        print('Requires one Developer ID Application identity; use KEYBAY_APPLE_TEAM_ID to select its team.')
        return 69
    certificate, team = matches[0]
    nonce = secrets.token_hex(32)
    identifier = 'dev.keybay.qualification.developerid.' + nonce
    base = Path(os.environ.get('KEYBAY_REGRESSION_DIR', repo / 'build'))
    base.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='macos-developer-id-', dir=base))
    binary = out / 'keybay-runtime'
    module = out / 'keybay.aot'
    control = out / 'control'
    report = {'kind': 'keybay-macos-developer-id-continuity', 'status': 'fail',
        'subject': subject, 'nonce': nonce, 'execution_class': 'native-host',
        'mode': 'Developer ID / hardened runtime and separate AOT module', 'artifacts': [], 'phases': [],
        'cleanup': 'not_observed', 'limitations': [
            'Unentitled login-Keychain profile on this account/OS; no notarization or entitled-app distribution claim.',
            'Same SDK/store format, signing certificate and designated requirement; no signing-team or format migration.',
            'No physical lock/reboot, backup/transfer, or per-app OS isolation claim.',
        ]}
    stage = 'prepare'
    build = None
    cleanup_binary = None
    cleanup_module = None
    cleanup_build = None

    def run(name, args, timeout=60):
        result = subprocess.run(args, cwd=repo, capture_output=True, timeout=timeout)
        (out / (name + '.log')).write_bytes(result.stdout + result.stderr)
        require(result.returncode == 0, 'command_failed')
        return result.stdout

    def settings():
        return [subprocess.check_output(['security', command, '-d', 'user'])
                for command in ('list-keychains', 'default-keychain')]

    def phase_run(phase, executable=None, snapshot=None, expected_build=None):
        with (out / (phase + '-stdout.log')).open('wb') as stdout, (out / (phase + '-stderr.log')).open('wb') as stderr:
            process = subprocess.Popen([str(executable or binary), str(snapshot or module), phase], stdout=stdout, stderr=stderr)
            try:
                code = process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise ValueError('phase_timeout') from None
        (out / (phase + '-native-exit.json')).write_text(json.dumps({'pid': process.pid, 'exit_code': code}) + '\n')
        require(code == 0, 'native_exit_failed')
        value = json.loads((out / (phase + '-stdout.log')).read_text())
        verify_receipt(value, nonce, subject, expected_build or build, phase, process.pid)
        (out / (phase + '-result.json')).write_text(json.dumps(value, indent=2) + '\n')
        return process.pid

    def sign(name, path, code_identifier):
        run(name + '-sign', ['codesign', '--force', '--sign', certificate, '--identifier', code_identifier,
                            '--options', 'runtime', '--timestamp', str(path)], 120)
        run(name + '-verify', ['codesign', '--verify', '--strict', '-R',
            '=anchor apple generic and identifier "' + code_identifier + '" and certificate leaf[subject.OU] = "' + team + '"', str(path)])
        details = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], capture_output=True, check=True)
        details_text = (details.stdout + details.stderr).decode()
        (out / (name + '-signature.log')).write_text(details_text)
        fields = dict(re.findall(r'^([^=\n]+)=(.*)$', details_text, re.MULTILINE))
        require(fields.get('TeamIdentifier') == team and fields.get('Identifier') == code_identifier and
                re.search(r'^CodeDirectory .*flags=.*runtime', details_text, re.MULTILINE) and
                fields.get('Timestamp'), 'wrong_signature')
        require('Authority=Developer ID Application:' in details_text, 'wrong_certificate_type')
        entitlements = run(name + '-entitlements', ['codesign', '-d', '--entitlements', ':-', str(path)])
        require(not entitlements.strip(), 'unexpected_entitlements')
        requirement = subprocess.run(['codesign', '-d', '-r-', str(path)], capture_output=True, check=True)
        designated = re.search(r'^designated => (.+)$', (requirement.stdout + requirement.stderr).decode(), re.MULTILINE)[1]
        return {'identifier': code_identifier, 'team': team, 'requirement': designated,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'cdhash': fields['CDHash'],
                'strict_signature_verified': True, 'secure_timestamp': fields['Timestamp'], 'entitlements_empty': True}

    before = settings()
    try:
        # Resolve the VM selected by `dart`, including distribution launchers.
        # An appended executable uses Dart's custom snapshot mapper. A separate
        # Mach-O module uses dyld and preserves signed executable page validation.
        probe = out / 'runtime_path.dart'
        probe.write_text("import 'dart:io'; void main() => stdout.write(Platform.resolvedExecutable);\n")
        runtime = Path(run('runtime-path', ['dart', '--suppress-analytics', 'run', str(probe)]).decode()).with_name('dartaotruntime')
        require(runtime.is_file(), 'missing_aot_runtime')
        shutil.copy2(runtime, binary)
        runtime_signature = sign('runtime', binary, identifier)
        pids = []
        for phase, build in [('seed', '101'), ('reopen', '102')]:
            stage = phase + '-build'
            run(stage, ['dart', 'compile', 'aot-snapshot', '-Dkeybay.application_id=' + identifier,
                '-DKEYBAY_SECURITY_NONCE=' + nonce, '-DKEYBAY_SECURITY_SUBJECT=' + subject,
                '-DKEYBAY_SECURITY_BUILD=' + build, '-DKEYBAY_SECURITY_CONTROL=' + str(control),
                'packages/keybay/test/support/macos_developer_id_harness.dart', '-o', str(module)], 300)
            stage = phase + '-sign'
            artifact = dict(sign(phase, module, identifier + '.code'), build=build, runtime=runtime_signature)
            if report['artifacts']:
                verify_artifacts(report['artifacts'][0], artifact)
            report['artifacts'].append(artifact)
            cleanup_binary = out / ('signed-build-' + build)
            cleanup_module = out / ('signed-build-' + build + '.aot')
            shutil.copy2(binary, cleanup_binary)
            shutil.copy2(module, cleanup_module)
            cleanup_build = build
            stage = phase
            pid = phase_run(phase)
            require(pid not in pids, 'same_process')
            pids.append(pid)
            report['phases'].append({'phase': phase, 'build': build, 'native_exit_code': 0})
            print('PASS: Developer ID SDK ' + phase, flush=True)
        require(not control.exists(), 'control_not_removed')
        require(not git('status', '--porcelain', '--untracked-files=all'), 'source_changed')
        report['status'] = 'pass'
        report['provider_store_stage_and_control_absent'] = True
        report['distinct_processes'] = True
        report['source_clean_after'] = True
        report['cleanup'] = 'verified'
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        report['failed_stage'] = stage
        report['failure_reason'] = str(error) if isinstance(error, ValueError) else type(error).__name__
    finally:
        if control.exists():
            try:
                phase_run('cleanup', cleanup_binary, cleanup_module, cleanup_build)
                require(not control.exists(), 'cleanup_incomplete')
                report['cleanup'] = 'verified_after_failure'
            except (ValueError, OSError, KeyError, subprocess.SubprocessError):
                report['cleanup'] = 'failed'
                report['status'] = 'fail'
        report['user_keychain_settings_preserved'] = settings() == before
        if not report['user_keychain_settings_preserved']:
            report['status'] = 'fail'
        report['recorded_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Developer ID report: ' + str(out / 'report.json'), flush=True)
    return 0 if report['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())

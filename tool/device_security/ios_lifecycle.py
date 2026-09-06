"""Physical iOS Profile/AOT continuity; called by the validated iOS adapter."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time

from lifecycle import require, verify_receipt, verify_upgrade

BUNDLE = "dev.keybay.securityharness"


def verify_process_presence(command, pid, *, present, executable=None):
    require(type(pid) is int and pid > 0, 'invalid_process_identity')
    require(command.get('info', {}).get('outcome') == 'success', 'process_inventory_failed')
    processes = command.get('result', {}).get('runningProcesses')
    require(type(processes) is list and all(type(p) is dict and type(p.get('processIdentifier')) is int for p in processes),
            'invalid_process_inventory')
    matches = [p for p in processes if p['processIdentifier'] == pid]
    require(len(matches) == (1 if present else 0), 'unexpected_process_presence')
    if present:
        require(type(executable) is str and executable and matches[0].get('executable') == executable,
                'process_executable_changed')


def verify_phase(command, receipt, nonce, subject, phase, mode="process", build="101"):
    """Launcher success alone cannot qualify an app process or a stale result."""
    require(command.get("info", {}).get("outcome") == "success", "launch_failed")
    result = command.get("result", {})
    code = result.get("terminationResult", {}).get("exitCode")
    require(type(code) is int and code == 0, "process_did_not_exit_successfully")
    pid = result.get("process", {}).get("processIdentifier")
    require(type(pid) is int and pid > 0, "missing_process_identity")
    require(verify_receipt(receipt, nonce, subject, phase, mode, build) == pid,
            "receipt_process_mismatch")
    return pid


def verify_cleanup(files):
    paths = {entry["relativePath"] for entry in files}
    require("keybay-lifecycle-result.json" in paths and not paths.intersection({
        "keybay-lifecycle-control.json", "keybay-v2/keybay.v2.store",
        "keybay-v2/keybay.v2.stage",
        "keybay-lifecycle-ack.json", "keybay-lifecycle-ack.json.stage",
    }), "fixture_cleanup_incomplete")


def main():
    os.umask(0o077)
    device, model, os_version, mode = sys.argv[1:]
    repo = Path(__file__).resolve().parents[2]
    harness = repo / "example_flutter"
    out = Path(os.environ["DEVICE_SECURITY_RUN_DIR"])
    nonce = os.environ["DEVICE_SECURITY_NONCE"]
    subject = os.environ["DEVICE_SECURITY_SOURCE_IDENTITY"]
    team = os.environ["KEYBAY_APPLE_TEAM_ID"]
    report = {
        "kind": "keybay-ios-" + mode + "-continuity", "status": "fail",
        "selection": mode, "artifacts": [],
        "execution_class": "physical-device", "mode": "Profile/AOT",
        "nonce": nonce, "subject": subject, "model": model, "os_version": os_version,
        "phases": [], "cleanup": "not_observed",
        "limitations": [
            "Apple Development signing; no distribution signing, reboot, relock, backup/transfer or access-group transition.",
            "Two exact SIGKILLs: after seed acknowledgment and during a bounded write workload; not power loss or a deterministic syscall interruption." if mode == "crash" else
            "Passphrase-protected upgrade between builds 101/102." if mode == "upgrade" else
            "Platform-protected continuity in one installed binary; no application update.",
        ],
    }
    stage = "prepare"
    installed = False

    def run(name, args, *, env=None, timeout=150):
        # Device identifiers and tool diagnostics stay in private artifacts.
        with (out / (name + ".log")).open("w") as log:
            result = subprocess.run(args, cwd=harness, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        require(result.returncode == 0, "command_failed")

    def native(name, args):
        output = out / (name + "-command-private.json")
        options = ['--device', device, '--timeout', '120', '--json-output', str(output)]
        position = args.index('--') if '--' in args else len(args)
        run(name, ['xcrun', 'devicectl', *args[:position], *options, *args[position:]])
        value = json.loads(output.read_text())
        require(value.get("info", {}).get("outcome") == "success", "device_command_failed")
        return value

    def copy_receipt(phase):
        target = out / (phase + "-result.json")
        native(phase + "-copy", ["device", "copy", "from",
               "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
               "--source", "Library/Application Support/keybay-lifecycle-result.json",
               "--destination", str(target)])
        return json.loads(target.read_text())

    def clean_source():
        return not subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=all"], cwd=repo)

    try:
        require(mode in ("process", "upgrade", "crash"), "invalid_mode")
        require(re.fullmatch(r"[A-Z0-9]{10}", team), "invalid_team")
        require(re.fullmatch(r"[0-9a-f]{64}", nonce), "invalid_nonce")
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
        require(subject == "git-commit:" + head and clean_source(), "source_mismatch")
        config = out / "signing.xcconfig"
        config.write_text("DEVELOPMENT_TEAM = " + team + "\n"
                          "CODE_SIGN_IDENTITY = Apple Development\nCODE_SIGN_STYLE = Automatic\n")
        env = dict(os.environ, XCODE_XCCONFIG_FILE=str(config))
        pids = []
        for phase in (("seed", "mutate", "reopen") if mode == "crash" else ("seed", "reopen")):
            build = "102" if mode == "upgrade" and phase == "reopen" else "101"
            if phase == "seed" or mode == "upgrade":
                stage = phase + "-build"
                run(stage, ["flutter", "build", "ios", "--profile", "--no-pub", "-t",
                            "lib/mobile_lifecycle_harness.dart",
                            "--dart-define=KEYBAY_SECURITY_NONCE=" + nonce,
                            "--dart-define=KEYBAY_SECURITY_SUBJECT=" + subject,
                            "--dart-define=KEYBAY_LIFECYCLE_MODE=" + mode,
                            "--dart-define=KEYBAY_LIFECYCLE_BUILD=" + build, "--build-number", build], env=env, timeout=900)
                stage = phase + "-signature"
                app = harness / "build/ios/iphoneos/Runner.app"
                expected = team + "." + BUNDLE
                run(stage, ["codesign", "--verify", "--deep", "--strict", "-R",
                            '=anchor apple generic and identifier "' + BUNDLE +
                            '" and certificate leaf[subject.OU] = "' + team + '"', str(app)])
                entitlements = plistlib.loads(subprocess.check_output(
                    ["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
                info = plistlib.loads((app / "Info.plist").read_bytes())
                groups = entitlements.get("keychain-access-groups")
                require(info.get("CFBundleIdentifier") == BUNDLE and
                        info.get("KeybayApplicationIdentifier") == expected and
                        entitlements.get("application-identifier") == expected and
                        (groups is None or groups == [expected]), "signed_identity_mismatch")
                artifact = {
                    "build_number": str(info["CFBundleVersion"]),
                    "strict_apple_signature_verified": True, "application_identifier": expected,
                    "keychain_access_groups": groups,
                    "executable_sha256": hashlib.sha256((app / info["CFBundleExecutable"]).read_bytes()).hexdigest(),
                    "aot_sha256": hashlib.sha256((app / "Frameworks/App.framework/App").read_bytes()).hexdigest(),
                }
                require(artifact["build_number"] == build, "wrong_signed_build")
                if phase == "reopen":
                    verify_upgrade(report["artifacts"][0], artifact, ("application_identifier", "keychain_access_groups"))
                report["artifacts"].append(artifact)
                stage = phase + "-install"
                native(stage, ["device", "install", "app", str(app)])
                installed = True
            stage = phase
            killed = mode == 'crash' and phase != 'reopen'
            report["cleanup"] = "unknown_until_reopen"
            command_path = out / (phase + "-command-private.json")
            # Launch options must precede '--'; these are real native app arguments.
            run(phase, ["xcrun", "devicectl", "device", "process", "launch",
                        "--device", device, *([] if killed else ["--console"]), "--timeout", "120",
                        "--json-output", str(command_path), BUNDLE,
                        "--", "--keybay-lifecycle-" + phase])
            command = json.loads(command_path.read_text())
            if killed:
                require(command.get('info', {}).get('outcome') == 'success', 'launch_failed')
                pid = command.get('result', {}).get('process', {}).get('processIdentifier')
                require(type(pid) is int and pid > 0 and pid not in pids, 'invalid_native_process')
                deadline = time.monotonic() + 60
                while True:
                    try:
                        receipt = copy_receipt(phase)
                        require(verify_receipt(receipt, nonce, subject, phase, mode, build) == pid,
                                'receipt_process_mismatch')
                        break
                    except (ValueError, KeyError, OSError, subprocess.SubprocessError):
                        if time.monotonic() >= deadline:
                            raise ValueError('phase_not_ready_for_kill') from None
                        time.sleep(0.5)
                inventory = native(phase + '-before-kill', ['device', 'info', 'processes'])
                verify_process_presence(inventory, pid, present=True,
                    executable=command['result']['process'].get('executable'))
                native(phase + '-kill', ['device', 'process', 'signal', '--pid', str(pid), '--signal', 'SIGKILL'])
                deadline = time.monotonic() + 30
                while True:
                    inventory = native(phase + '-after-kill', ['device', 'info', 'processes'])
                    try:
                        verify_process_presence(inventory, pid, present=False)
                        break
                    except ValueError:
                        if time.monotonic() >= deadline:
                            raise ValueError('native_kill_did_not_qualify') from None
                        time.sleep(0.5)
            else:
                receipt = copy_receipt(phase)
                pid = verify_phase(command, receipt, nonce, subject, phase, mode, build)
            require(pid not in pids, "process_not_changed")
            pids.append(pid)
            report["phases"].append(dict(phase=phase, build=build, status='pass',
                **({'native_signal': 'SIGKILL', 'native_process_absence_verified': True} if killed else {'native_exit_code': 0})))
            print("PASS: physical iOS " + phase, flush=True)
        report["distinct_processes"] = True
        stage = "cleanup"
        inventory = native(stage, ["device", "info", "files", "--domain-type", "appDataContainer",
                           "--domain-identifier", BUNDLE, "--subdirectory", "Library/Application Support",
                           "--recurse"])
        verify_cleanup(inventory["result"]["files"])
        report["cleanup"] = "app_reported_reset_and_verified_file_absence"
        stage = "source_verification"
        require(clean_source(), "source_changed_during_run")
        report["source_clean_after"] = True
        report["status"] = "pass"
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        # Exception details may include the private device ID or native diagnostics.
        report["failed_stage"] = stage
    finally:
        if mode == 'crash' and installed and report['status'] != 'pass':
            try:
                command = native('failure-cleanup', ['device', 'process', 'launch',
                    '--terminate-existing', '--console', BUNDLE, '--', '--keybay-lifecycle-cleanup'])
                verify_phase(command, copy_receipt('cleanup'), nonce, subject, 'cleanup', mode, '101')
                inventory = native('failure-cleanup-files', ['device', 'info', 'files', '--domain-type',
                    'appDataContainer', '--domain-identifier', BUNDLE, '--subdirectory',
                    'Library/Application Support', '--recurse'])
                verify_cleanup(inventory['result']['files'])
                report['cleanup'] = 'verified_after_failure'
            except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
                report['cleanup'] = 'failed'
        report["recorded_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print("Device-security report: " + str(out / "report.json"), flush=True)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())

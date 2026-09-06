"""Physical Android Profile/AOT continuity; called by the validated adapter."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

from lifecycle import require, verify_receipt, verify_upgrade

PACKAGE = "dev.keybay.securityharness"


def verify_exit(history, pid, uid, user, killed=False):
    # ApplicationExitInfo's dump format is platform-specific. Unknown or changed
    # formats fail closed. REASON_EXIT_SELF=1 and status=0 mean normal exit(0).
    records = []
    for block in re.split(r"ApplicationExitInfo #\d+:\s*", history)[1:]:
        fields = dict(re.findall(r"\b(pid|realUid|packageUid|user|process|reason|status)=([^\s]+)", block))
        if fields.get("pid") == str(pid):
            records.append(fields)
    require(len(records) == 1, "missing_or_duplicate_exit")
    expected = {"pid": str(pid), "realUid": str(uid), "packageUid": str(uid),
                "user": str(user), "process": PACKAGE,
                "reason": "2" if killed else "1", "status": "9" if killed else "0"}
    require(records[0] == expected, "unexpected_native_exit")


def verify_cleanup(paths):
    names = set(paths.splitlines())
    require("no_backup/keybay-lifecycle-result.json" in names and not names.intersection({
        "no_backup/keybay-lifecycle-control.json", "no_backup/keybay-v2/keybay.v2.store",
        "no_backup/keybay-v2/keybay.v2.stage",
        "no_backup/keybay-lifecycle-ack.json", "no_backup/keybay-lifecycle-ack.json.stage",
    }), "fixture_cleanup_incomplete")


def main():
    os.umask(0o077)
    device, user, model, release, api, mode = sys.argv[1:]
    repo = Path(__file__).resolve().parents[2]
    harness = repo / "example_flutter"
    out = Path(os.environ["DEVICE_SECURITY_RUN_DIR"])
    nonce = os.environ["DEVICE_SECURITY_NONCE"]
    subject = os.environ["DEVICE_SECURITY_SOURCE_IDENTITY"]
    report = {
        "kind": "keybay-android-" + mode + "-continuity", "status": "fail",
        "selection": mode, "artifacts": [],
        "execution_class": "physical-device", "mode": "Profile/AOT",
        "nonce": nonce, "subject": subject, "model": model, "os_version": release,
        "api_level": int(api), "phases": [], "cleanup": "not_observed",
        "limitations": [
            "Debug-signed debuggable Profile/AOT harness; no reboot, relock, backup/transfer or peer-app procedure.",
            "Two exact SIGKILLs: after seed acknowledgment and during a bounded write workload; not power loss or a deterministic syscall interruption." if mode == "crash" else
            "Passphrase-protected upgrade between builds 101/102." if mode == "upgrade" else
            "Platform-protected continuity in one installed APK; no application update.",
            "Hardware-key properties remain in the separate baseline.",
        ],
    }
    stage = "prepare"
    install_attempted = False

    def run(name, args, *, timeout=30, check=True):
        result = subprocess.run(args, cwd=harness, capture_output=True, timeout=timeout)
        (out / (name + ".log")).write_bytes(result.stdout + result.stderr)
        if check:
            require(result.returncode == 0, "command_failed")
        return result

    def adb(name, args, **kwargs):
        return run(name, ["adb", "-s", device, *args], **kwargs)

    def app_files(name, args, **kwargs):
        return adb(name, ["exec-out", "run-as", PACKAGE, "--user", user, *args], **kwargs)

    def clean_source():
        return not subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=all"], cwd=repo)

    try:
        require(mode in ("process", "upgrade", "crash"), "invalid_mode")
        require(re.fullmatch(r"[0-9a-f]{64}", nonce), "invalid_nonce")
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
        require(subject == "git-commit:" + head and clean_source(), "source_mismatch")
        sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if not sdk:
            properties = (harness / "android/local.properties").read_text()
            sdk = re.search(r"^sdk.dir=(.+)$", properties, re.MULTILINE)[1]
        candidates = [p for p in (Path(sdk) / "build-tools").iterdir()
                      if re.fullmatch(r"\d+\.\d+\.\d+", p.name)]
        build_tools = max(candidates, key=lambda p: tuple(map(int, p.name.split("."))))
        pids = []
        for phase in (("seed", "mutate", "reopen") if mode == "crash" else ("seed", "reopen")):
            build = "102" if mode == "upgrade" and phase == "reopen" else "101"
            if phase == "seed" or mode == "upgrade":
                stage = phase + "-build"
                run(stage, ["flutter", "build", "apk", "--profile", "--no-pub", "--target-platform", "android-arm64",
                            "-t", "lib/mobile_lifecycle_harness.dart",
                            "--dart-define=KEYBAY_SECURITY_NONCE=" + nonce,
                            "--dart-define=KEYBAY_SECURITY_SUBJECT=" + subject,
                            "--dart-define=KEYBAY_LIFECYCLE_MODE=" + mode,
                            "--dart-define=KEYBAY_LIFECYCLE_BUILD=" + build, "--build-number", build], timeout=900)
                apk = harness / "build/app/outputs/flutter-apk/app-profile.apk"
                stage = phase + "-apk_verification"
                signature = run(phase + "-signature", [str(build_tools / "apksigner"), "verify", "--print-certs", str(apk)]).stdout.decode()
                certificates = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})$", signature, re.MULTILINE)
                require(len(certificates) == 1, "missing_or_multiple_signers")
                badging = run(phase + "-badging", [str(build_tools / "aapt"), "dump", "badging", str(apk)]).stdout.decode()
                require(re.search(r"^package: name='" + re.escape(PACKAGE) + r"' ", badging, re.MULTILINE) and
                        "application-debuggable" in badging, "wrong_apk_identity_or_not_inspectable")
                with zipfile.ZipFile(apk) as archive:
                    aot = archive.read("lib/arm64-v8a/libapp.so")
                artifact = {"build_number": re.search(r"^package: .*versionCode='([0-9]+)'", badging, re.MULTILINE)[1],"package": PACKAGE, "signature_verified": True,
                                      "signer_sha256": certificates[0], "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
                                      "aot_sha256": hashlib.sha256(aot).hexdigest(), "build_tools": build_tools.name}
                require(artifact["build_number"] == build, "wrong_signed_build")
                if phase == "reopen":
                    verify_upgrade(report["artifacts"][0], artifact, ("package", "signer_sha256"))
                report["artifacts"].append(artifact)
                stage = phase + "-install"
                install_attempted = True
                adb(stage, ["install", *(["-r"] if phase == "reopen" else []), "--user", user, str(apk)], timeout=120)
                installed_uid = int(app_files(phase + "-app-uid", ["id", "-u"]).stdout.strip())
                if phase == "reopen":
                    require(uid == installed_uid, "upgrade_uid_changed")
                uid = installed_uid
            stage = phase
            killed = mode == 'crash' and phase != 'reopen'
            adb(phase + "-launch", ["shell", "am", "start", "-W", "--user", user, "-n", PACKAGE + "/.MainActivity",
                                    "--es", "keybayLifecyclePhase", phase])
            deadline = time.monotonic() + 60
            while True:
                try:
                    receipt = app_files(phase + "-receipt", ["cat", "no_backup/keybay-lifecycle-result.json"])
                    receipt_value = json.loads(receipt.stdout)
                    pid = verify_receipt(receipt_value, nonce, subject, phase, mode, build)
                    if killed:
                        state = adb(phase + "-process-before-kill", ["shell", "pidof", PACKAGE])
                        require(state.stdout.strip() == str(pid).encode() and pid not in pids,
                                "wrong_process_before_kill")
                        break
                    history = adb(phase + "-exit-info", ["shell", "dumpsys", "activity", "exit-info", PACKAGE]).stdout.decode()
                    verify_exit(history, pid, uid, user)
                    state = adb(phase + "-process", ["shell", "pidof", PACKAGE], check=False)
                    require(state.returncode == 1 and not state.stdout.strip(), "process_not_absent")
                    break
                except (ValueError, OSError, subprocess.SubprocessError):
                    if time.monotonic() >= deadline:
                        raise ValueError("phase_did_not_qualify") from None
                    time.sleep(0.5)
            if killed:
                # run-as limits the signal to the fixture's own UID. Signal the
                # exact acknowledged process once; retries only observe its exit.
                app_files(phase + '-kill', ['kill', '-9', str(pid)])
                deadline = time.monotonic() + 30
                while True:
                    try:
                        history = adb(phase + '-exit-info', ['shell', 'dumpsys', 'activity', 'exit-info', PACKAGE]).stdout.decode()
                        verify_exit(history, pid, uid, user, killed=True)
                        state = adb(phase + '-process', ['shell', 'pidof', PACKAGE], check=False)
                        require(state.returncode == 1 and not state.stdout.strip(), 'process_not_absent')
                        break
                    except (ValueError, OSError, subprocess.SubprocessError):
                        if time.monotonic() >= deadline:
                            raise ValueError('native_kill_did_not_qualify') from None
                        time.sleep(0.5)
            require(pid not in pids, "process_not_changed")
            pids.append(pid)
            (out / (phase + "-result.json")).write_text(json.dumps(receipt_value, indent=2) + "\n")
            report["phases"].append(dict(phase=phase, build=build, status='pass',
                **({'native_exit_reason': 'SIGNALED', 'native_signal': 9} if killed else
                   {'native_exit_reason': 'EXIT_SELF', 'native_exit_code': 0})))
            print("PASS: physical Android " + phase, flush=True)
        report["distinct_processes"] = True
        stage = "file_cleanup"
        inventory = app_files(stage, ["find", "no_backup", "-print"]).stdout.decode()
        verify_cleanup(inventory)
        report["control_store_and_staging_absent"] = True
        stage = "source_verification"
        require(clean_source(), "source_changed_during_run")
        report["source_clean_after"] = True
        report["status"] = "pass"
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError, zipfile.BadZipFile):
        report["failed_stage"] = stage
    finally:
        if install_attempted:
            try:
                adb("uninstall", ["uninstall", "--user", user, PACKAGE])
                remaining = adb("package-cleanup", ["shell", "pm", "list", "packages", "--user", user, PACKAGE]).stdout.strip()
                require(not remaining, "package_cleanup_failed")
                report["cleanup"] = "dedicated_package_uninstalled_and_absence_verified"
            except (ValueError, OSError, subprocess.SubprocessError):
                report["status"] = "fail"
                report["cleanup"] = "failed"
        report["recorded_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print("Device-security report: " + str(out / "report.json"), flush=True)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())

"""Exercise real runner orchestration with fake native commands, never devices."""
import contextlib
import io
import itertools
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool/device_security"))
import android_lifecycle
import ios_lifecycle
import macos_developer_id

PACKAGE = "dev.keybay.securityharness"
TEAM = "AAAAAAAAAA"
HEAD = "b" * 40
NONCE = "a" * 64


class DeveloperIdEvidenceTest(unittest.TestCase):
    def test_requires_changed_code_and_stable_identity(self):
        seed = dict(build='101', sha256='a', cdhash='b', identifier='app', team='team', requirement='requirement', runtime={'sha256': 'runtime'})
        reopen = dict(seed, build='102', sha256='c', cdhash='d')
        macos_developer_id.verify_artifacts(seed, reopen)
        for field in ['build', 'sha256', 'cdhash', 'identifier', 'team', 'requirement', 'runtime']:
            altered = dict(reopen)
            altered[field] = seed[field] if field in ['build', 'sha256', 'cdhash'] else 'different'
            with self.assertRaises(ValueError):
                macos_developer_id.verify_artifacts(seed, altered)

    def test_requires_exact_success_and_native_process(self):
        receipt = dict(kind='keybay-macos-developer-id', nonce=NONCE, subject=HEAD,
                       build='102', phase='reopen', pid=1234, status='pass')
        macos_developer_id.verify_receipt(receipt, NONCE, HEAD, '102', 'reopen', 1234)
        for field, value in [('status', 'fail'), ('phase', 'seed'), ('pid', 1235), ('nonce', 'old'), ('extra', True)]:
            with self.assertRaises(ValueError):
                macos_developer_id.verify_receipt(dict(receipt, **{field: value}), NONCE, HEAD, '102', 'reopen', 1234)


class RunnerTest(unittest.TestCase):
    def exercise(self, platform, mode, failure=None):
        module = ios_lifecycle if platform == "ios" else android_lifecycle
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = root / "out"
            out.mkdir()
            tools = root / "sdk/build-tools/36.0.0"
            tools.mkdir(parents=True)
            harness = root / "example_flutter"
            harness.mkdir()
            state = {"builds": [], "installs": [], "phases": [], "data": False, "uninstalls": 0, "running": False, "kills": []}
            env = {"DEVICE_SECURITY_RUN_DIR": str(out), "DEVICE_SECURITY_NONCE": NONCE,
                   "DEVICE_SECURITY_SOURCE_IDENTITY": "git-commit:" + HEAD,
                   "KEYBAY_APPLE_TEAM_ID": TEAM, "ANDROID_HOME": str(root / "sdk")}
            argv = ["runner", "fake-device", "model", "os", mode] if platform == "ios" else [
                "runner", "fake-device", "0", "model", "16", "36", mode]

            def output(args, **kwargs):
                if args[0] == "git":
                    value = HEAD + "\n" if args[1] == "rev-parse" else ""
                    return value if kwargs.get("text") else value.encode()
                self.assertEqual(args[:3], ["codesign", "-d", "--entitlements"])
                return plistlib.dumps({"application-identifier": TEAM + "." + PACKAGE})

            def run(args, **kwargs):
                value, code = b"", 0
                program = Path(args[0]).name
                if program == "flutter":
                    build = args[args.index("--build-number") + 1]
                    self.assertIn("--dart-define=KEYBAY_LIFECYCLE_BUILD=" + build, args)
                    self.assertIn("--dart-define=KEYBAY_LIFECYCLE_MODE=" + mode, args)
                    state["build"] = build
                    state["builds"].append(build)
                    aot = ("101" if failure == "same_binary" else build).encode()
                    app = harness / "build/ios/iphoneos/Runner.app"
                    (app / "Frameworks/App.framework").mkdir(parents=True, exist_ok=True)
                    (app / "Frameworks/App.framework/App").write_bytes(aot)
                    (app / "Runner").write_bytes(aot)
                    (app / "Info.plist").write_bytes(plistlib.dumps({
                        "CFBundleIdentifier": PACKAGE, "KeybayApplicationIdentifier": TEAM + "." + PACKAGE,
                        "CFBundleVersion": build, "CFBundleExecutable": "Runner"}))
                    apk = harness / "build/app/outputs/flutter-apk/app-profile.apk"
                    apk.parent.mkdir(parents=True, exist_ok=True)
                    with zipfile.ZipFile(apk, "w") as archive:
                        archive.writestr("lib/arm64-v8a/libapp.so", aot)
                elif program == "apksigner":
                    value = ("Signer #1 certificate SHA-256 digest: " + "c" * 64 + "\n").encode()
                elif program == "aapt":
                    value = ("package: name='" + PACKAGE + "' versionCode='" + state["build"] + "'\napplication-debuggable\n").encode()
                elif program == "codesign":
                    pass
                elif program in ("adb", "xcrun"):
                    native_json = {"info": {"outcome": "success"}, "result": {}}
                    if "install" in args:
                        if state["installs"]:
                            self.assertEqual(state["phases"], ["seed"])
                            self.assertTrue(state["data"], "seed data cleared before upgrade")
                            if platform == "android": self.assertIn("-r", args)
                        state["installs"].append(state["build"])
                    elif "start" in args or "launch" in args:
                        phase = args[-1].removeprefix("--keybay-lifecycle-")
                        state["phases"].append(phase)
                        if phase in ("mutate", "reopen"): self.assertTrue(state["data"])
                        state["data"] = phase in ("seed", "mutate")
                        state["pid"] = 123 if failure == "same_pid" else {'seed': 123, 'mutate': 124, 'reopen': 125, 'cleanup': 126}[phase]
                        interrupted = mode == 'crash' and phase in ('seed', 'mutate')
                        state['running'] = interrupted
                        state["receipt"] = {"kind": "keybay-mobile-lifecycle", "nonce": NONCE,
                            "subject": "git-commit:" + HEAD, "phase": phase, "mode": mode,
                            "build": state["build"], "pid": state["pid"],
                            "status": "ready" if interrupted else "pass", "reason": "awaiting_termination" if interrupted else "completed"}
                        native_json["result"] = {"process": {"processIdentifier": state["pid"], 'executable': 'file:///fixture/Runner.app/Runner'}, "terminationResult": {"exitCode": 0}}
                        if failure == 'stale_ready' and interrupted:
                            state['receipt']['nonce'] = 'old'
                    elif "copy" in args:
                        Path(args[args.index("--destination") + 1]).write_text(json.dumps(state["receipt"]))
                    elif "cat" in args:
                        value = json.dumps(state["receipt"]).encode()
                    elif "id" in args:
                        value = b"10456\n"
                    elif "kill" in args or "signal" in args:
                        expected_pid = args[args.index('--pid') + 1] if platform == 'ios' else args[-1]
                        self.assertEqual(expected_pid, str(state['pid']))
                        self.assertTrue(state['running'])
                        self.assertTrue('--signal' in args if platform == 'ios' else '-9' in args)
                        state['kills'].append(state['pid'])
                        state['running'] = failure == 'survives_kill'
                    elif "processes" in args:
                        executable = 'file:///unrelated' if failure == 'wrong_executable' else 'file:///fixture/Runner.app/Runner'
                        native_json['result'] = {'runningProcesses': [{'processIdentifier': state['pid'], 'executable': executable}] if state['running'] else []}
                    elif "exit-info" in args:
                        killed = state['pid'] in state['kills']
                        value = ("ApplicationExitInfo #0:\n pid=" + str(state["pid"]) +
                                 " realUid=10456 packageUid=10456 user=0\n process=" + PACKAGE +
                                 (" reason=2 (SIGNALED) status=9\n" if killed else " reason=1 (EXIT_SELF) status=0\n")).encode()
                    elif "pidof" in args:
                        code = 0 if state['running'] else 1
                        value = str(state['pid']).encode() if state['running'] else b''
                    elif "find" in args or "files" in args:
                        paths = ["keybay-lifecycle-result.json", "keybay-v2/keybay.v2.lock"]
                        if failure == "leftover": paths.append("keybay-v2/keybay.v2.stage")
                        value = "\n".join("no_backup/" + p for p in paths).encode()
                        native_json["result"] = {"files": [{"relativePath": p} for p in paths]}
                    elif "uninstall" in args:
                        self.assertEqual(state["uninstalls"], 0)
                        state["uninstalls"] += 1
                        if failure == "uninstall": code = 1
                    elif "packages" in args:
                        pass
                    else:
                        self.fail("unexpected native command: " + str(args))
                    if "--json-output" in args:
                        Path(args[args.index("--json-output") + 1]).write_text(json.dumps(native_json))
                else:
                    self.fail("unexpected command: " + str(args))
                return subprocess.CompletedProcess(args, code, value, b"")

            with patch.object(module, "__file__", str(root / "tool/device_security/runner.py")), \
                 patch.dict(os.environ, env), patch.object(sys, "argv", argv), \
                 patch("subprocess.check_output", side_effect=output), patch("subprocess.run", side_effect=run), \
                 patch('time.monotonic', side_effect=itertools.count(0, 120)), patch('time.sleep'), \
                 contextlib.redirect_stdout(io.StringIO()):
                result = module.main()
            report = json.loads((out / "report.json").read_text())
            self.assertEqual(result, 1 if failure else 0)
            self.assertEqual(report["status"], "fail" if failure else "pass")
            if not failure:
                self.assertEqual(state["builds"], ["101", "102"] if mode == "upgrade" else ["101"])
                self.assertEqual(state["installs"], state["builds"])
                self.assertEqual(state["phases"], ["seed", "mutate", "reopen"] if mode == 'crash' else ["seed", "reopen"])
                self.assertEqual(state['kills'], [123, 124] if mode == 'crash' else [])
            if platform == "android": self.assertEqual(state["uninstalls"], 1)
            if failure == 'stale_ready':
                self.assertEqual(state['kills'], [])
                if platform == 'ios': self.assertEqual(report['cleanup'], 'verified_after_failure')
            if failure == 'survives_kill': self.assertEqual(state['kills'], [123])
            if failure == 'wrong_executable': self.assertEqual(state['kills'], [])

    def test_both_runners(self):
        for platform in ("android", "ios"):
            for mode in ("process", "upgrade", "crash"):
                with self.subTest(platform=platform, mode=mode):
                    self.exercise(platform, mode)
            for failure in ("same_binary", "same_pid", "leftover"):
                with self.subTest(platform=platform, failure=failure):
                    self.exercise(platform, "upgrade", failure)
            self.exercise(platform, 'crash', 'stale_ready')
            self.exercise(platform, 'crash', 'survives_kill')
        self.exercise('ios', 'crash', 'wrong_executable')
        self.exercise("android", "upgrade", "uninstall")


class CrashEvidenceTest(unittest.TestCase):
    def test_process_inventory_must_be_complete_and_exact(self):
        good = {'info': {'outcome': 'success'}, 'result': {'runningProcesses': [
            {'processIdentifier': 123, 'executable': 'file:///fixture'}]}}
        ios_lifecycle.verify_process_presence(good, 123, present=True, executable='file:///fixture')
        for command in [{}, {'info': {'outcome': 'success'}, 'result': {}},
                        dict(good, result={'runningProcesses': [{}]}),
                        dict(good, result={'runningProcesses': good['result']['runningProcesses'] * 2}),
                        dict(good, info={'outcome': 'failure'})]:
            with self.assertRaises(ValueError):
                ios_lifecycle.verify_process_presence(command, 123, present=True, executable='file:///fixture')
        with self.assertRaises(ValueError):
            ios_lifecycle.verify_process_presence(good, 123, present=False)
        ios_lifecycle.verify_process_presence(dict(good, result={'runningProcesses': []}), 123, present=False)

    def test_android_signal_is_distinct_from_clean_exit(self):
        history = ('ApplicationExitInfo #0: pid=123 realUid=10456 packageUid=10456 user=0 '
                   'process=' + PACKAGE + ' reason=2 (SIGNALED) status=9')
        android_lifecycle.verify_exit(history, 123, 10456, '0', killed=True)
        for bad in [history.replace('reason=2', 'reason=1'), history.replace('status=9', 'status=0'), history + history]:
            with self.assertRaises(ValueError):
                android_lifecycle.verify_exit(bad, 123, 10456, '0', killed=True)


if __name__ == "__main__":
    unittest.main()

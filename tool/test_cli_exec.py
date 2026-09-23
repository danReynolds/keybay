#!/usr/bin/env python3
"""Black-box execve and manifest tests for the compiled Keybay CLI."""

from __future__ import annotations

import os
import errno
import pty
import resource
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def run(
    cli: str,
    manifest: Path | None,
    *command: str,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    preexec_fn=None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [cli, "run", *([] if manifest is None else ["-f", str(manifest)]), "--", *command],
        cwd=cwd,
        env=env,
        preexec_fn=preexec_fn,
        text=True,
        capture_output=True,
        check=False,
        timeout=10,
    )


def executable(path: Path, source: str) -> None:
    path.write_text(source, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def assert_result(
    result: subprocess.CompletedProcess[str],
    status: int,
    *,
    stdout: str | None = None,
    stderr_contains: str | None = None,
) -> None:
    if result.returncode != status:
        raise AssertionError(
            f"status {result.returncode}, expected {status}\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
    if stdout is not None and result.stdout != stdout:
        raise AssertionError(f"stdout {result.stdout!r}, expected {stdout!r}")
    if stderr_contains is not None and stderr_contains not in result.stderr:
        raise AssertionError(
            f"stderr did not contain {stderr_contains!r}: {result.stderr!r}"
        )


def read_pty(fd: int, needle: bytes, timeout: float = 5.0) -> bytes:
    deadline = time.monotonic() + timeout
    output = bytearray()
    while needle not in output and time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.05)
        if not readable:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        output.extend(chunk)
    if needle not in output:
        raise AssertionError(f"PTY output missing {needle!r}: {bytes(output)!r}")
    return bytes(output)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} KEYBAY", file=sys.stderr)
        return 2
    cli = os.path.abspath(sys.argv[1])

    with tempfile.TemporaryDirectory(prefix="keybay-cli-exec-") as raw_tmp:
        tmp = Path(raw_tmp)
        empty = tmp / "empty.env"
        empty.write_text("", encoding="utf-8")
        mixed = tmp / "mixed.env"
        mixed.write_text(
            "PATH=/usr/bin:/bin\n"
            "KEYBAY_LITERAL=from-manifest\n"
            "EMPTY=\n",
            encoding="utf-8",
        )

        usage = subprocess.run(
            [cli], text=True, capture_output=True, check=False
        )
        assert_result(usage, 2, stderr_contains="Try keybay --help")

        argv_sentinel = "must-not-echo-this-argument"
        bad_set = subprocess.run(
            [cli, "set", "acme/key", argv_sentinel],
            text=True,
            capture_output=True,
            check=False,
        )
        assert_result(bad_set, 2)
        if argv_sentinel in bad_set.stderr:
            raise AssertionError("usage error echoed an unexpected value argument")

        captured_get = subprocess.run(
            [cli, "get", "acme/key"],
            text=True,
            capture_output=True,
            check=False,
        )
        assert_result(captured_get, 4, stderr_contains="captured output is refused")

        # Invalid value channels must fail before real-provider access.
        non_tty_set = subprocess.run([cli, "set", "acme/key"], input="ignored",
                                     text=True, capture_output=True, timeout=10)
        assert_result(non_tty_set, 4, stderr_contains="controlling foreground TTY")

        fifo = tmp / "manifest.fifo"
        os.mkfifo(fifo)
        for invalid in [fifo, tmp, Path("/dev/null")]:
            assert_result(run(cli, invalid, "/usr/bin/true"), 2,
                          stderr_contains="regular file")
        symlink = tmp / "manifest-link"
        symlink.symlink_to(empty)
        assert_result(run(cli, symlink, "/usr/bin/true"), 0)

        # Even a manifest referencing secrets cannot reach the provider when
        # its initial executable cannot be resolved.
        protected = tmp / "references.env"
        protected.write_text("TOKEN=kb://acme/key\n", encoding="utf-8")
        assert_result(run(cli, protected, "/absent/keybay-test-command"), 127)

        inherited = dict(os.environ)
        inherited["KEYBAY_LITERAL"] = "from-parent"
        result = run(cli, mixed, "printenv", "KEYBAY_LITERAL", env=inherited)
        assert_result(result, 0, stdout="from-manifest\n")

        # Parent variables that are not valid UTF-8 (legal in POSIX; dropped
        # entirely by Dart's Platform.environment) pass through byte-exact —
        # the executor builds the child environment from raw environ.
        raw_env = dict(os.environ)
        raw_env["KEYBAY_RAW_BYTES"] = b"pre\xffpost".decode(
            "utf-8", "surrogateescape"
        )
        result = run(
            cli,
            empty,
            "sh",
            "-c",
            "printenv KEYBAY_RAW_BYTES | od -An -tx1",
            env=raw_env,
        )
        raw_hex = "".join(result.stdout.split())
        if result.returncode != 0 or raw_hex != "707265ff706f73740a":
            raise AssertionError(
                f"non-UTF-8 parent value did not pass through byte-exact: "
                f"status={result.returncode} hex={raw_hex!r}"
            )

        # A manifest overlay still replaces a byte-shadowed parent entry.
        raw_overlay_env = dict(os.environ)
        raw_overlay_env["KEYBAY_LITERAL"] = b"raw\xffparent".decode(
            "utf-8", "surrogateescape"
        )
        result = run(
            cli, mixed, "printenv", "KEYBAY_LITERAL", env=raw_overlay_env
        )
        assert_result(result, 0, stdout="from-manifest\n")

        # Keybay disables its own core files, but the launched program keeps
        # the caller's soft core-file limit.
        _, hard_core = resource.getrlimit(resource.RLIMIT_CORE)
        caller_core = 4096 if hard_core == resource.RLIM_INFINITY else min(hard_core, 4096)
        if caller_core > 0:
            core_limit = run(
                cli,
                empty,
                sys.executable,
                "-c",
                "import resource;print(resource.getrlimit(resource.RLIMIT_CORE)[0])",
                preexec_fn=lambda: resource.setrlimit(
                    resource.RLIMIT_CORE, (caller_core, hard_core)
                ),
            )
            assert_result(core_limit, 0, stdout=f"{caller_core}\n")

        # The child starts with shell-default signal state: the VM's ignored
        # SIGPIPE is reset (a pipeline member dies 141, not an EPIPE error) and
        # the VM's blocked job-control signals are unmasked.
        result = run(
            cli,
            empty,
            "sh",
            "-c",
            "(yes 2>/dev/null; echo rc=$? >&2) | head -n 1 >/dev/null",
        )
        assert_result(result, 0, stderr_contains="rc=141")
        result = run(
            cli,
            empty,
            sys.executable,
            "-c",
            "import signal;"
            "print(len(signal.pthread_sigmask(signal.SIG_BLOCK, set())))",
        )
        assert_result(result, 0, stdout="0\n")

        result = run(cli, mixed, "/usr/bin/printf", "%s:%s", "argv", "kept")
        assert_result(result, 0, stdout="argv:kept")

        result = run(cli, empty, "/usr/bin/false")
        assert_result(result, 1)

        result = run(cli, empty, "definitely-not-a-keybay-command")
        assert_result(result, 127, stderr_contains="command not found")

        invalid_manifest = tmp / "invalid.env"
        manifest_sentinel = "manifest-secret-must-not-echo"
        invalid_manifest.write_text(
            f"INVALID NAME={manifest_sentinel}\n", encoding="utf-8"
        )
        result = run(cli, invalid_manifest, "/usr/bin/true")
        assert_result(result, 2, stderr_contains="invalid manifest")
        if manifest_sentinel in result.stderr:
            raise AssertionError("manifest diagnostic echoed source bytes")

        nested = tmp / "nested"
        nested.mkdir()
        (tmp / ".env").write_text("VALUE=parent\n", encoding="utf-8")
        for name in (".secrets.env", ".env.local", ".env.production", ".env.example"):
            (nested / name).write_text(
                "VALUE=alternate\nALTERNATE_ONLY=from-alternate\n", encoding="utf-8"
            )

        # Only .env in the working directory is implicit. Neither a parent
        # .env nor any other filename is a fallback when it is missing.
        no_default = run(cli, None, "/usr/bin/printf", "launched", cwd=nested)
        assert_result(no_default, 2, stdout="", stderr_contains="could not be read")

        default = nested / ".env"
        default.write_text("VALUE=current\nDEFAULT_ONLY=from-default\n", encoding="utf-8")
        assert_result(
            run(cli, None, "/usr/bin/printenv", "VALUE", cwd=nested),
            0, stdout="current\n",
        )
        clean_env = dict(os.environ)
        clean_env.pop("DEFAULT_ONLY", None)
        clean_env.pop("ALTERNATE_ONLY", None)
        assert_result(
            run(cli, None, "/usr/bin/printenv", "ALTERNATE_ONLY", cwd=nested, env=clean_env),
            1, stdout="",
        )

        # Explicit files replace the default completely, including arbitrary
        # filenames and the former default. No default-only values leak in.
        for name in (".env.production", ".secrets.env"):
            assert_result(
                run(cli, Path(name), "/usr/bin/printenv", "VALUE", cwd=nested),
                0, stdout="alternate\n",
            )
        assert_result(
            run(cli, Path(".env.production"), "/usr/bin/printenv", "DEFAULT_ONLY",
                cwd=nested, env=clean_env),
            1, stdout="",
        )

        # A selected file that is missing or invalid must not fall back to a
        # valid .env (or to a valid alternative when .env itself is invalid).
        assert_result(
            run(cli, Path("missing.env"), "/usr/bin/printf", "launched", cwd=nested),
            2, stdout="", stderr_contains="could not be read",
        )
        malformed = nested / "malformed.env"
        malformed.write_text("INVALID NAME=value\n", encoding="utf-8")
        assert_result(
            run(cli, malformed, "/usr/bin/printf", "launched", cwd=nested),
            2, stdout="", stderr_contains="invalid manifest",
        )
        default.write_text("INVALID NAME=value\n", encoding="utf-8")
        assert_result(
            run(cli, None, "/usr/bin/printf", "launched", cwd=nested),
            2, stdout="", stderr_contains="invalid manifest",
        )
        assert_result(
            run(cli, Path(".env.production"), "/usr/bin/printenv", "VALUE", cwd=nested),
            0, stdout="alternate\n",
        )

        no_path = tmp / "no-path.env"
        no_path.write_text("PATH=\n", encoding="utf-8")
        result = run(cli, no_path, "printenv", "PATH")
        assert_result(result, 0, stdout="\n")
        unset = dict(os.environ)
        unset.pop("PATH", None)
        assert_result(run(cli, mixed, "printenv", env=unset), 127)

        local_tool = tmp / "local-tool"
        executable(local_tool, "#!/bin/sh\nprintf cwd-ok\n")
        inherited_cwd = dict(os.environ, PATH=":/usr/bin")
        assert_result(run(cli, mixed, "local-tool", cwd=tmp, env=inherited_cwd), 0, stdout="cwd-ok")
        inherited_cwd["PATH"] = ""
        assert_result(run(cli, mixed, "local-tool", cwd=tmp, env=inherited_cwd), 0, stdout="cwd-ok")

        relative_bin = tmp / "relative-bin"
        relative_bin.mkdir()
        relative_tool = relative_bin / "relative-tool"
        executable(relative_tool, "#!/bin/sh\nprintf relative-ok\n")
        relative_path = tmp / "relative.env"
        relative_path.write_text("PATH=/manifest-must-not-select\n", encoding="utf-8")
        result = run(cli, relative_path, "relative-tool", cwd=tmp,
                     env=dict(os.environ, PATH="relative-bin"))
        assert_result(result, 0, stdout="relative-ok")
        assert_result(run(cli, relative_path, "./relative-bin/relative-tool", cwd=tmp), 0, stdout="relative-ok")
        dangling = tmp / "dangling"
        dangling.symlink_to(tmp / "absent")
        assert_result(run(cli, empty, str(dangling)), 127)
        assert_result(run(cli, empty, str(relative_bin)), 126)

        denied = tmp / "not-executable"
        denied.write_text("must never run\n", encoding="utf-8")
        result = run(cli, empty, str(denied))
        assert_result(result, 126, stderr_contains="not executable")

        no_shebang = tmp / "no-shebang"
        executable(no_shebang, "echo shell-fallback-must-not-run\n")
        result = run(cli, empty, str(no_shebang))
        assert_result(result, 126, stderr_contains="not executable")
        if "shell-fallback-must-not-run" in result.stdout:
            raise AssertionError("ENOEXEC incorrectly fell back to a shell")

        pid_helper = tmp / "pid-helper"
        executable(
            pid_helper,
            "#!/usr/bin/env python3\n"
            "import os, signal\n"
            "print(os.getpid(), flush=True)\n"
            "signal.pause()\n",
        )
        process = subprocess.Popen(
            [cli, "run", "-f", str(empty), "--", str(pid_helper)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert process.stdout is not None
        child_pid = int(process.stdout.readline().strip())
        if child_pid != process.pid:
            process.kill()
            raise AssertionError(
                f"keybay remained as wrapper pid {process.pid}; child was {child_pid}"
            )
        os.kill(process.pid, signal.SIGTERM)
        status = process.wait(timeout=5)
        if status != -signal.SIGTERM:
            raise AssertionError(f"signal status {status}, expected {-signal.SIGTERM}")

        tty_helper = tmp / "tty-helper"
        executable(
            tty_helper,
            "#!/usr/bin/env python3\n"
            "import os\n"
            "print(f'tty:{int(os.isatty(0))}{int(os.isatty(1))}{int(os.isatty(2))}')\n",
        )
        tty_pid, tty_master = pty.fork()
        if tty_pid == 0:
            os.execl(
                cli,
                cli,
                "run",
                "-f",
                str(empty),
                "--",
                str(tty_helper),
            )
        tty_output = read_pty(tty_master, b"tty:111")
        _, tty_status = os.waitpid(tty_pid, 0)
        if os.waitstatus_to_exitcode(tty_status) != 0:
            raise AssertionError(f"TTY child failed: {tty_output!r}")
        os.close(tty_master)

    print("CLI execve checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

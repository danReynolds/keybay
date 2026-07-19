#!/usr/bin/env python3
"""Regression tests for exact-content pub archive reconciliation."""

from __future__ import annotations

import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

sys.dont_write_bytecode = True

from compare_pub_archives import ArchiveError, canonical_digest


def _write_archive(
    path: pathlib.Path,
    *,
    content: bytes = b"name: example\nversion: 1.2.3\n",
    mode: int = 0o644,
    mtime: int = 1,
    duplicate: bool = False,
    member_name: str = "pubspec.yaml",
    member_type: bytes = tarfile.REGTYPE,
) -> None:
    with tarfile.open(path, "w:gz") as archive:
        directory = tarfile.TarInfo("lib")
        directory.type = tarfile.DIRTYPE
        directory.mode = 0o755
        directory.mtime = mtime
        archive.addfile(directory)

        member = tarfile.TarInfo(member_name)
        member.type = member_type
        member.mode = mode
        member.mtime = mtime
        member.uid = mtime
        member.gid = mtime
        member.size = len(content) if member_type == tarfile.REGTYPE else 0
        archive.addfile(member, io.BytesIO(content) if member.size else None)
        if duplicate:
            archive.addfile(member, io.BytesIO(content))


def _reject(path: pathlib.Path, case: str) -> None:
    try:
        canonical_digest(path)
    except ArchiveError:
        return
    raise AssertionError(f"unsafe {case} archive was accepted")


def _write_executable(path: pathlib.Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def _run_publish_case(
    repo: pathlib.Path,
    tmp: pathlib.Path,
    expected: pathlib.Path,
    hosted: pathlib.Path,
    status: int,
) -> tuple[subprocess.CompletedProcess[str], str]:
    log = tmp / "dart.log"
    log.write_text("")
    environment = {
        **os.environ,
        "PATH": f"{tmp / 'bin'}:{os.environ['PATH']}",
        "TEST_EXPECTED_ARCHIVE": str(expected),
        "TEST_HOSTED_ARCHIVE": str(hosted),
        "TEST_HTTP_STATUS": str(status),
        "TEST_LOG": str(log),
    }
    result = subprocess.run(
        ["./tool/publish_pubdev.sh", str(tmp / "package")],
        cwd=repo,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    return result, log.read_text()


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="keybay-pub-archives.") as raw_tmp:
        tmp = pathlib.Path(raw_tmp)
        expected = tmp / "expected.tar.gz"
        same_contents = tmp / "same-contents.tar.gz"
        changed_contents = tmp / "changed-contents.tar.gz"
        changed_mode = tmp / "changed-mode.tar.gz"
        _write_archive(expected, mtime=1)
        _write_archive(same_contents, mtime=2)
        _write_archive(changed_contents, content=b"name: wrong\n", mtime=2)
        _write_archive(changed_mode, mode=0o755, mtime=2)

        if canonical_digest(expected) != canonical_digest(same_contents):
            raise AssertionError("volatile tar metadata changed the content digest")
        if canonical_digest(expected) == canonical_digest(changed_contents):
            raise AssertionError("changed file bytes matched the expected archive")
        if canonical_digest(expected) == canonical_digest(changed_mode):
            raise AssertionError("changed file mode matched the expected archive")

        duplicate = tmp / "duplicate.tar.gz"
        traversal = tmp / "traversal.tar.gz"
        symlink = tmp / "symlink.tar.gz"
        _write_archive(duplicate, duplicate=True)
        _write_archive(traversal, member_name="../pubspec.yaml")
        _write_archive(symlink, member_type=tarfile.SYMTYPE)
        _reject(duplicate, "duplicate-member")
        _reject(traversal, "path-traversal")
        _reject(symlink, "symbolic-link")

        too_many = tmp / "too-many-members.tar.gz"
        with tarfile.open(too_many, "w:gz") as archive:
            for index in range(10_001):
                member = tarfile.TarInfo(f"directory-{index}")
                member.type = tarfile.DIRTYPE
                archive.addfile(member)
        _reject(too_many, "member-count")

        package = tmp / "package"
        package.mkdir()
        (package / "pubspec.yaml").write_text("name: example\nversion: 1.2.3\n")
        fake_bin = tmp / "bin"
        fake_bin.mkdir()
        _write_executable(
            fake_bin / "dart",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$TEST_LOG"
for argument in "$@"; do
  case "$argument" in
    --to-archive=*) cp "$TEST_EXPECTED_ARCHIVE" "${argument#*=}"; exit 0 ;;
    --from-archive=*) printf 'uploaded\\n' >> "$TEST_LOG"; exit 0 ;;
  esac
done
exit 2
""",
        )
        _write_executable(
            fake_bin / "curl",
            """#!/usr/bin/env bash
set -euo pipefail
output=
while [[ $# -gt 0 ]]; do
  if [[ "$1" = --output ]]; then output="$2"; shift 2; else shift; fi
done
if [[ "$TEST_HTTP_STATUS" = 200 ]]; then
  cp "$TEST_HOSTED_ARCHIVE" "$output"
else
  : > "$output"
fi
printf '%s' "$TEST_HTTP_STATUS"
""",
        )

        result, log = _run_publish_case(
            repo, tmp, expected, same_contents, 200
        )
        if result.returncode != 0 or "uploaded" in log:
            raise AssertionError(f"exact hosted archive was not reconciled: {result.stderr}")
        result, _ = _run_publish_case(repo, tmp, expected, changed_contents, 200)
        if result.returncode == 0:
            raise AssertionError("mismatched hosted archive was reconciled")
        result, log = _run_publish_case(repo, tmp, expected, same_contents, 404)
        if result.returncode != 0 or "uploaded" not in log:
            raise AssertionError(f"missing pub version was not uploaded: {result.stderr}")
        result, log = _run_publish_case(repo, tmp, expected, same_contents, 500)
        if result.returncode == 0 or "uploaded" in log:
            raise AssertionError("unexpected pub.dev response triggered publication")

    print("pub archive reconciliation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

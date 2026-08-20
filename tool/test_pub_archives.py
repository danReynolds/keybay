#!/usr/bin/env python3
"""Regression tests for exact-content pub archive reconciliation."""

from __future__ import annotations

import io
import hashlib
import pathlib
import subprocess
import sys
import tarfile
import tempfile

sys.dont_write_bytecode = True

from compare_pub_archives import ArchiveError, canonical_digest, canonical_identity


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
        if hashlib.sha256(canonical_identity(expected)).hexdigest() != canonical_digest(
            expected
        ):
            raise AssertionError("canonical identity bytes did not reproduce the digest")

        identity = tmp / "identity"
        result = subprocess.run(
            [
                sys.executable,
                str(repo / "tool" / "compare_pub_archives.py"),
                "--identity",
                str(expected),
                str(identity),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise AssertionError(f"identity command failed: {result.stderr}")
        if hashlib.sha256(identity.read_bytes()).hexdigest() != canonical_digest(
            expected
        ):
            raise AssertionError("identity command emitted the wrong bytes")

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

    print("pub archive comparison passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

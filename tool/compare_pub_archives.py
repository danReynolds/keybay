#!/usr/bin/env python3
"""Compare pub archives by package contents, ignoring volatile timestamps."""

from __future__ import annotations

import hashlib
import pathlib
import sys
import tarfile

_MAX_MEMBERS = 10_000
_MAX_CONTENT_BYTES = 256 * 1024 * 1024
_CHUNK_BYTES = 1024 * 1024


class ArchiveError(ValueError):
    """The archive is malformed or contains an unsafe member."""


def _field(digest: hashlib._Hash, value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def canonical_digest(path: pathlib.Path) -> str:
    """Hash every path, type, mode, and file byte in a safe pub archive."""
    records: dict[str, tuple[bytes, int, int, bytes]] = {}
    total_bytes = 0
    try:
        # Stream members so the count limit applies before tarfile can retain an
        # attacker-controlled number of headers in memory.
        with tarfile.open(path, "r|gz") as archive:
            for index, member in enumerate(archive):
                if index >= _MAX_MEMBERS:
                    raise ArchiveError(
                        f"too many archive members: more than {_MAX_MEMBERS}"
                    )
                name = member.name
                parts = name.split("/")
                if (
                    not name
                    or name.startswith("/")
                    or "\\" in name
                    or any(part in ("", ".", "..") for part in parts)
                ):
                    raise ArchiveError(f"unsafe archive path: {name!r}")
                if name in records:
                    raise ArchiveError(f"duplicate archive member: {name!r}")
                if not (member.isfile() or member.isdir()):
                    raise ArchiveError(f"unsupported archive member: {name!r}")
                if member.isdir():
                    if member.size != 0:
                        raise ArchiveError(
                            f"directory member carries data: {name!r}"
                        )
                    records[name] = (b"directory", member.mode & 0o7777, 0, b"")
                    continue

                if member.size < 0:
                    raise ArchiveError(f"negative archive member size: {name!r}")
                total_bytes += member.size
                if total_bytes > _MAX_CONTENT_BYTES:
                    raise ArchiveError("archive contents exceed the safety limit")
                source = archive.extractfile(member)
                if source is None:
                    raise ArchiveError(f"could not read archive member: {name!r}")
                file_digest = hashlib.sha256()
                bytes_read = 0
                with source:
                    while chunk := source.read(_CHUNK_BYTES):
                        bytes_read += len(chunk)
                        file_digest.update(chunk)
                if bytes_read != member.size:
                    raise ArchiveError(f"truncated archive member: {name!r}")
                records[name] = (
                    b"file",
                    member.mode & 0o7777,
                    member.size,
                    file_digest.digest(),
                )
    except ArchiveError:
        raise
    except (OSError, EOFError, tarfile.TarError) as error:
        raise ArchiveError(f"could not read {path}: {error}") from error
    digest = hashlib.sha256()
    for name in sorted(records):
        kind, mode, size, content_digest = records[name]
        _field(digest, kind)
        _field(digest, name.encode("utf-8", "surrogateescape"))
        _field(digest, mode.to_bytes(2, "big"))
        if kind == b"directory":
            _field(digest, b"")
        else:
            _field(digest, size.to_bytes(8, "big"))
            _field(digest, content_digest)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_pub_archives.py EXPECTED.tar.gz HOSTED.tar.gz", file=sys.stderr)
        return 2
    expected = pathlib.Path(sys.argv[1])
    hosted = pathlib.Path(sys.argv[2])
    try:
        expected_digest = canonical_digest(expected)
        hosted_digest = canonical_digest(hosted)
    except ArchiveError as error:
        print(f"pub archive comparison failed: {error}", file=sys.stderr)
        return 1
    if expected_digest != hosted_digest:
        print("hosted pub archive does not match the tagged package contents", file=sys.stderr)
        print(f"expected: {expected_digest}", file=sys.stderr)
        print(f"hosted:   {hosted_digest}", file=sys.stderr)
        return 1
    print(f"hosted pub archive matches tagged contents: {expected_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

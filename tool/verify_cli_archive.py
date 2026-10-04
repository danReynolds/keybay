#!/usr/bin/env python3
"""Strict, non-executing and non-extracting release archive validation."""
import pathlib
import json
import sys
import tarfile
from cli_hardware_bundle import MANIFEST, digest, manifest_files

BASE = {"LICENSE": "file", "README.md": "file", "keybay": "file",
        "example": "directory", "example/quickstart": "directory",
        **{f"example/quickstart/{n}": "file" for n in ("README.md", ".env", "app.sh")}}


def verify(path):
    with tarfile.open(path, "r:gz") as archive:
        members = {}
        # Iterate with a count and size bound before reading any member bodies.
        for member in archive:
            if len(members) >= 20 or member.size > 128 * 1024 * 1024:
                raise ValueError("oversized release archive")
            if member.name in members:
                raise ValueError(f"duplicate member {member.name!r}")
            members[member.name] = member
            if not member.isfile() and not member.isdir():
                raise ValueError(f"unsafe member {member.name!r}")
        metadata = members.get(MANIFEST)
        if metadata is None or not metadata.isfile() or metadata.size > 16384:
            raise ValueError("missing or invalid hardware manifest")
        files = manifest_files(archive.extractfile(metadata).read())
        runtime = ({'keybay-runtime': 'file', 'keybay.aot': 'file', 'LICENSE.dart': 'file'}
                   if json.loads(archive.extractfile(metadata).read())['platform'] == 'macos' else {})
        expected = runtime | BASE | {MANIFEST: "file"} | {name: "file" for name in files}
        if members.keys() != expected.keys():
            raise ValueError("unexpected or missing archive members")
        for name, kind in expected.items():
            item = members[name]
            if ("file" if item.isfile() else "directory") != kind:
                raise ValueError(f"incorrect member type: {name}")
            if item.mode & 0o7000:
                raise ValueError(f"unexpected special mode: {name}")
        for name, hash_value in files.items():
            if digest(archive.extractfile(members[name]).read()) != hash_value:
                raise ValueError(f"hardware digest mismatch: {name}")
        for name in ["keybay", "example/quickstart/app.sh", *(["keybay-runtime"] if runtime else [])]:
            if not members[name].mode & 0o111:
                raise ValueError(f"not executable: {name}")
        root = pathlib.Path(__file__).resolve().parent.parent / "packages/keybay_cli"
        for name in ("README.md", ".env", "app.sh"):
            relative = f"example/quickstart/{name}"
            if archive.extractfile(members[relative]).read() != (root / relative).read_bytes():
                raise ValueError(f"changed packaged example: {name}")


if __name__ == "__main__":
    try:
        verify(sys.argv[1])
    except (OSError, tarfile.TarError, ValueError, TypeError, KeyError) as error:
        raise SystemExit(f"invalid release archive: {error}") from error
    print("CLI release archive passed")

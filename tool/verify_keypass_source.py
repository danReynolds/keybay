#!/usr/bin/env python3
"""Verify reviewed native build inputs from the hosted Keypass package."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def verify(source: Path, manifest: dict) -> None:
    # The manifest is checked into Keybay, never supplied by the dependency.
    expected = manifest["files"]
    native = source / "native/hardware"
    paths = [source / "LICENSE", source / "pubspec.yaml", native,
             *native.rglob("*")]
    if any(path.is_symlink() for path in [source / "native", *paths]):
        raise ValueError("Keypass native build inputs contain a symlink")
    files = {path.relative_to(source).as_posix(): path
             for path in paths if path.is_file()}
    if set(files) != set(expected):
        raise ValueError("Keypass native build input set changed")
    for name, path in files.items():
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected[name]:
            raise ValueError(f"Keypass native build input changed: {name}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_keypass_source.py PACKAGE_DIRECTORY", file=sys.stderr)
        return 2
    try:
        manifest = json.loads(Path(__file__).with_name("keypass-source.json").read_text())
        verify(Path(sys.argv[1]), manifest)
        print(f"Verified Keypass {manifest['version']} native source ({manifest['revision']}).")
    except (OSError, ValueError) as error:
        print(f"invalid Keypass source: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

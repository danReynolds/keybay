#!/usr/bin/env python3
"""Inspect and install disposable CLI test bundles.

Keypass owns native dependency bundling. RK owns release artifacts.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

REVISION = json.loads(pathlib.Path(__file__).with_name("keypass-source.json").read_text())["revision"]
MANIFEST = "hardware.json"
NOTICES = "THIRD_PARTY_NOTICES.txt"
# Keypass bundles OpenSSL 3 or 4, whichever libfido2 links.
MAC = (r"libkeypass_hardware\.dylib", r"libfido2\.1\.dylib",
       r"libcrypto\.[34]\.dylib", r"libcbor\.[0-9.]+\.dylib")
LINUX = (r"libkeypass_hardware\.so", r"libfido2\.so\.1",
         r"libcrypto\.so\.[34]", r"libcbor\.so\.[0-9.]+")

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def manifest_files(data: bytes, *, require_current=True) -> dict[str, str]:
    if len(data) > 16384:
        raise ValueError("oversized hardware manifest")
    item = json.loads(data)
    if not isinstance(item, dict):
        raise ValueError("invalid hardware manifest")
    if item.get("schema") != 1 or not re.fullmatch(r"[a-f0-9]{40}", str(item.get("keypassRevision"))) or (require_current and item["keypassRevision"] != REVISION):
        raise ValueError("unexpected hardware manifest version or Keypass revision")
    patterns = {"macos": MAC, "linux": LINUX}.get(item.get("platform"))
    files = item.get("files")
    if patterns is None or not isinstance(files, dict) or len(files) != 5:
        raise ValueError("invalid hardware file set")
    if item.get("architecture") not in ("arm64", "x64"):
        raise ValueError("unsupported hardware architecture")
    names = set(files) - {NOTICES}
    if len(names) != 4 or any(sum(bool(re.fullmatch(p, n)) for n in names) != 1 for p in patterns):
        raise ValueError("unexpected native library names")
    if any(not isinstance(h, str) or not re.fullmatch(r"[a-f0-9]{64}", h) for h in files.values()):
        raise ValueError("invalid hardware file digest")
    return files


def verify(directory: pathlib.Path) -> dict[str, str]:
    files = manifest_files((directory / MANIFEST).read_bytes())
    libraries = {p.name for pattern in ('*.dylib', '*.so', '*.so.*') for p in directory.glob(pattern)}
    if libraries != set(files) - {NOTICES}:
        raise ValueError("unexpected or missing native companions")
    for name, expected in files.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != expected:
            raise ValueError(f"hardware bundle file mismatch: {name}")
    return files


def install(source: pathlib.Path, target: pathlib.Path) -> None:
    files = verify(source)
    target.mkdir(parents=True, exist_ok=True)
    if (target / MANIFEST).exists():
        previous = manifest_files((target / MANIFEST).read_bytes(), require_current=False)
        for name in set(previous) - set(files):
            (target / name).unlink(missing_ok=True)
    # Fresh inodes avoid macOS's cache of signatures on previously run files.
    for name in [*files, MANIFEST]:
        with tempfile.NamedTemporaryFile(dir=target, delete=False) as stage:
            temporary = pathlib.Path(stage.name)
        try:
            shutil.copy2(source / name, temporary)
            temporary.replace(target / name)
        finally:
            temporary.unlink(missing_ok=True)
    verify(target)


def main() -> None:
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "verify":
            verify(pathlib.Path(sys.argv[2]))
        elif len(sys.argv) == 4 and sys.argv[1] == "install":
            install(*map(pathlib.Path, sys.argv[2:]))
        else:
            raise ValueError("usage: cli_hardware_bundle.py verify DIR | install SOURCE TARGET")
    except (ValueError, OSError) as error:
        raise SystemExit(f"invalid hardware bundle: {error}") from error


if __name__ == "__main__":
    main()

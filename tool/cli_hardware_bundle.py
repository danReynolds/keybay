#!/usr/bin/env python3
"""Build/inspect the CLI's relocatable native dependency bundle.

Archive validation uses only bytes and metadata; it never loads a candidate.
Native inspection/rewriting is restricted to libraries produced by our build.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REVISION = "e5fbdda99639d0b0693b3b0f60ca9825cd5fc336"
MANIFEST = "hardware.json"
NOTICES = "THIRD_PARTY_NOTICES.txt"
MAC = (r"libkeypass_hardware\.dylib", r"libfido2\.1\.dylib",
       r"libcrypto\.3\.dylib", r"libcbor\.[0-9.]+\.dylib")
LINUX = (r"libkeypass_hardware\.so", r"libfido2\.so\.1",
         r"libcrypto\.so\.3", r"libcbor\.so\.[0-9.]+")
LINUX_SYSTEM = re.compile(r"^(lib(c|m|dl|rt|pthread|stdc\+\+|gcc_s|udev|z|zstd)\.so\.[0-9]+|ld-linux[^/]*\.so\.[0-9]+)$")


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


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


def dependencies(path: pathlib.Path, mac: bool) -> list[str]:
    if mac:
        # First entry is the library's own install name.
        return [line.strip().split(" (", 1)[0] for line in run("otool", "-L", str(path)).splitlines()[2:]]
    return re.findall(r"\(NEEDED\).*\[([^\]]+)\]", run("readelf", "-d", str(path)))


def is_system(name: str, mac: bool) -> bool:
    return (name.startswith(("/usr/lib/", "/System/Library/")) if mac
            else bool(LINUX_SYSTEM.fullmatch(name)))


def bundle(source: pathlib.Path, output: pathlib.Path, notices: pathlib.Path) -> None:
    mac = sys.platform == "darwin"
    if not mac and sys.platform != "linux":
        raise ValueError("hardware bundling supports macOS and Linux")
    patterns = MAC if mac else LINUX
    output.mkdir(parents=True, exist_ok=True)
    # Clean only a previous bundle's explicitly listed generated files.
    if (output / MANIFEST).exists():
        for name in manifest_files((output / MANIFEST).read_bytes(), require_current=False):
            (output / name).unlink(missing_ok=True)
        (output / MANIFEST).unlink()
    pending = [(source.name, source)]
    copied = set()
    while pending:
        name, original = pending.pop()
        if name in copied:
            continue
        if not any(re.fullmatch(pattern, name) for pattern in patterns):
            raise ValueError(f"unexpected native dependency {name}")
        target = output / name
        if target.is_symlink():
            raise ValueError(f"bundle target is a symlink: {target}")
        shutil.copyfile(original, target)
        target.chmod(0o755)
        copied.add(name)
        deps = dependencies(original, mac)
        # ldd is used only on the trusted freshly built library, never archives.
        resolved = {} if mac else dict(re.findall(r"^\s*(\S+) => (\S+)", run("ldd", str(original)), re.M))
        for dep in deps:
            if is_system(dep, mac):
                continue
            path = pathlib.Path(dep if mac else resolved.get(dep, ""))
            if not path.is_absolute() or not path.is_file():
                raise ValueError(f"cannot resolve native dependency {dep}")
            pending.append((path.name, path))
            if mac:
                subprocess.run(["install_name_tool", "-change", dep, f"@loader_path/{path.name}", str(target)], check=True)
        if mac:
            subprocess.run(["install_name_tool", "-id", f"@rpath/{name}", str(target)], check=True)
            load = run("otool", "-l", str(target))
            for rpath in re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+) \(offset", load):
                subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(target)], check=True)
            # Rewriting invalidates existing signatures. Release signing follows.
            subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True)
        else:
            subprocess.run(["patchelf", "--set-rpath", "$ORIGIN", str(target)], check=True)
    shutil.copyfile(notices, output / NOTICES)
    machine = run("uname", "-m")
    item = {"schema": 1, "keypassRevision": REVISION,
            "platform": "macos" if mac else "linux",
            "architecture": {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64"}[machine],
            "files": {name: digest((output / name).read_bytes()) for name in sorted(copied | {NOTICES})}}
    (output / MANIFEST).write_text(json.dumps(item, indent=2) + "\n")
    verify(output)
    for name in copied:
        for dep in dependencies(output / name, mac):
            if not is_system(dep, mac) and (dep.removeprefix("@loader_path/") not in copied or (mac and not dep.startswith("@loader_path/"))):
                raise ValueError(f"unbundled dependency {dep}")


def main() -> None:
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "verify":
            verify(pathlib.Path(sys.argv[2]))
        elif len(sys.argv) == 5 and sys.argv[1] == "build":
            bundle(*map(pathlib.Path, sys.argv[2:]))
        elif len(sys.argv) == 4 and sys.argv[1] == "install":
            install(*map(pathlib.Path, sys.argv[2:]))
        else:
            raise ValueError("usage: cli_hardware_bundle.py build LIB OUTPUT NOTICES | verify DIR | install SOURCE TARGET")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"invalid hardware bundle: {error}") from error


if __name__ == "__main__":
    main()

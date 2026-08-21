#!/usr/bin/env python3
"""Report drift from explicitly reviewed security-critical package pins."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

CONFIG_PATH = pathlib.Path(__file__).with_name("config.json")
_PACKAGE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
_VERSION = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$")


def pub_latest(name: str) -> str:
    request = urllib.request.Request(
        f"https://pub.dev/api/packages/{name}",
        headers={"User-Agent": "keybay-security-watchers/1"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        try:
            payload = json.load(response)
        except json.JSONDecodeError as error:
            raise urllib.error.URLError(
                f"non-JSON pub.dev response: {error}"
            ) from error
    try:
        version = payload["latest"]["version"]
    except (KeyError, TypeError) as error:
        raise urllib.error.URLError("pub.dev response had no latest version") from error
    if not isinstance(version, str) or not _VERSION.fullmatch(version):
        raise urllib.error.URLError(f"pub.dev returned an unsafe version: {version!r}")
    return version


def findings(config: dict[str, object]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    packages = config.get("packages")
    if not isinstance(packages, list) or not packages:
        raise ValueError("critical watcher needs a non-empty packages list")
    for package in packages:
        if not isinstance(package, dict):
            raise ValueError("critical package definition must be an object")
        ecosystem = package.get("ecosystem")
        name = package.get("name")
        reviewed = package.get("reviewed_version")
        url = package.get("url")
        if ecosystem != "Pub" or not isinstance(name, str) or not _PACKAGE.fullmatch(name):
            raise ValueError(f"unsupported critical package: {package!r}")
        if not isinstance(reviewed, str) or not _VERSION.fullmatch(reviewed):
            raise ValueError(f"invalid reviewed version for {name}")
        if url != f"https://pub.dev/packages/{name}":
            raise ValueError(f"invalid package URL for {name}")
        latest = pub_latest(name)
        if latest == reviewed:
            continue
        marker_version = re.sub(r"[^0-9A-Za-z_.-]", "-", latest)
        result.append(
            {
                "watcher": "critical",
                "marker": f"keybay-critical-pub-{name}-{marker_version}",
                "title": f"Critical dependency review: {name} {latest}",
                "subjects": [
                    f"Pub/{name}: reviewed {reviewed}; published {latest}"
                ],
                "references": [{"label": f"Pub/{name}", "url": url}],
            }
        )
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit issue-ready JSON and return 0 when the source was reachable",
    )
    args = parser.parse_args(argv)
    try:
        config = json.loads(CONFIG_PATH.read_text())
        found = findings(config)
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError) as error:
        print(f"critical-dependencies: source or configuration invalid: {error}", file=sys.stderr)
        return 69
    if args.json:
        json.dump(found, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if not found:
        print("critical-dependencies: every reviewed pin is still current")
        return 0
    for finding in found:
        print(f"critical-dependencies: REVIEW REQUIRED: {finding['title']}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

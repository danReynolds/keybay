#!/usr/bin/env python3
"""Peer-advisory watch: an oracle, not a dependency feed.

Queries OSV for advisories against the named peer secret-storage libraries and
compares the IDs to the reviewed pre-automation baseline beside this script.
A new ID is free red-team output against Keybay's own failure surface. GitHub
issues, including closed dispositions, are the durable record after that
baseline; routine triage never requires editing a repository ledger.

Default output exits 0 when quiet and 1 for new IDs. `--json` returns 0 for any
successful query so the workflow can create or deduplicate issues. Exit 69
means OSV was unreachable — a watch that cannot watch never reports quiet.
"""
import argparse
import json
import pathlib
import sys
import urllib.error

from watchers import osv

PEERS = [
    ("Pub", "flutter_secure_storage"),
    ("PyPI", "keyring"),
    ("npm", "keytar"),
    ("Go", "github.com/zalando/go-keyring"),
    ("crates.io", "keyring"),
]
BASELINE_PATH = pathlib.Path(__file__).with_name("baseline.json")


def advisories(ecosystem: str, name: str) -> set[str]:
    return {str(record["id"]) for record in osv.query_package(ecosystem, name)}


def new_advisories(baseline: set[str]) -> dict[str, list[str]]:
    new: dict[str, set[str]] = {}
    for ecosystem, name in PEERS:
        for advisory_id in advisories(ecosystem, name) - baseline:
            new.setdefault(advisory_id, set()).add(f"{ecosystem}/{name}")
    return {
        advisory_id: sorted(packages)
        for advisory_id, packages in sorted(new.items())
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit issue-ready JSON and return 0 when OSV was reachable",
    )
    args = parser.parse_args(argv)
    baseline = set(json.loads(BASELINE_PATH.read_text())["baseline"])
    try:
        new = new_advisories(baseline)
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"peer-advisories: OSV unreachable or invalid: {error}", file=sys.stderr)
        return 69

    if args.json:
        json.dump(
            [
                {
                    "watcher": "peers",
                    "marker": f"keybay-peer-osv-{advisory_id}",
                    "title": f"Peer advisory triage: {advisory_id}",
                    "subjects": packages,
                    "references": [
                        {
                            "label": advisory_id,
                            "url": f"https://osv.dev/vulnerability/{advisory_id}",
                        }
                    ],
                }
                for advisory_id, packages in new.items()
            ],
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0
    if not new:
        print("peer-advisories: no new advisories across "
              f"{len(PEERS)} watched packages")
        return 0
    print("peer-advisories: NEW advisory IDs — triage against the invariants, "
          "record the decision in the generated GitHub issue:")
    for advisory_id, packages in new.items():
        print(f"  {advisory_id}: {', '.join(packages)} "
              f"(https://osv.dev/vulnerability/{advisory_id})")
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Peer-advisory watch: an oracle, not a feed.

Queries OSV for advisories against the named peer secret-storage libraries and
compares the IDs to the reviewed seen-list beside this script. A new ID is
free red-team output against Keybay's own failure surface: triage it against
the invariants, record the applicability decision, then add the ID to the
seen-list in the same change.

Exit 0: nothing new. Exit 1: new advisory IDs (printed). Exit 69: OSV was
unreachable — a watch that cannot watch must not report quiet success.
"""
import json
import pathlib
import sys
import urllib.error
import urllib.request

PEERS = [
    ("Pub", "flutter_secure_storage"),
    ("PyPI", "keyring"),
    ("npm", "keytar"),
    ("Go", "github.com/zalando/go-keyring"),
    ("crates.io", "keyring"),
]
SEEN_PATH = pathlib.Path(__file__).with_name("peer_advisories_seen.json")


def advisories(ecosystem: str, name: str) -> set[str]:
    ids: set[str] = set()
    page_token = None
    while True:
        query = {"package": {"name": name, "ecosystem": ecosystem}}
        if page_token:
            query["page_token"] = page_token
        request = urllib.request.Request(
            "https://api.osv.dev/v1/query",
            data=json.dumps(query).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            try:
                payload = json.load(response)
            except json.JSONDecodeError as error:
                # A captive portal or outage page must read as
                # "watch could not watch" (69), never as "new advisories" (1).
                raise urllib.error.URLError(f"non-JSON OSV response: {error}")
        ids.update(vuln["id"] for vuln in payload.get("vulns") or [])
        page_token = payload.get("next_page_token")
        if not page_token:
            return ids


def main() -> int:
    seen = set(json.loads(SEEN_PATH.read_text())["seen"])
    new: dict[str, list[str]] = {}
    for ecosystem, name in PEERS:
        try:
            found = advisories(ecosystem, name)
        except (urllib.error.URLError, TimeoutError) as error:
            print(f"peer-advisories: OSV unreachable for {ecosystem}/{name}: "
                  f"{error}", file=sys.stderr)
            return 69
        fresh = sorted(found - seen)
        if fresh:
            new[f"{ecosystem}/{name}"] = fresh
    if not new:
        print("peer-advisories: no new advisories across "
              f"{len(PEERS)} watched packages")
        return 0
    print("peer-advisories: NEW advisory IDs — triage against the invariants, "
          "record the decision, then add the IDs to "
          f"{SEEN_PATH.name}:")
    for package, ids in sorted(new.items()):
        for advisory_id in ids:
            print(f"  {package}: {advisory_id} "
                  f"(https://osv.dev/vulnerability/{advisory_id})")
    return 1


if __name__ == "__main__":
    sys.exit(main())

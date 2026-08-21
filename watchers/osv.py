"""Small, fail-loud OSV client shared by repository watchers."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

_ADVISORY_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")


def query_package(ecosystem: str, name: str) -> list[dict[str, object]]:
    """Return every OSV record for a package, following pagination."""

    records: list[dict[str, object]] = []
    page_token: str | None = None
    while True:
        query: dict[str, object] = {
            "package": {"name": name, "ecosystem": ecosystem}
        }
        if page_token:
            query["page_token"] = page_token
        request = urllib.request.Request(
            "https://api.osv.dev/v1/query",
            data=json.dumps(query).encode(),
            headers={
                "Content-Type": "application/json",
                "User-Agent": "keybay-security-watchers/1",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            try:
                payload = json.load(response)
            except json.JSONDecodeError as error:
                raise urllib.error.URLError(
                    f"non-JSON OSV response: {error}"
                ) from error
        if not isinstance(payload, dict):
            raise urllib.error.URLError("OSV response was not an object")
        vulnerabilities = payload.get("vulns") or []
        if not isinstance(vulnerabilities, list):
            raise urllib.error.URLError("OSV vulnerabilities was not a list")
        for vulnerability in vulnerabilities:
            if not isinstance(vulnerability, dict):
                raise urllib.error.URLError("OSV vulnerability was not an object")
            advisory_id = vulnerability.get("id")
            if not isinstance(advisory_id, str) or not _ADVISORY_ID.fullmatch(
                advisory_id
            ):
                raise urllib.error.URLError(
                    f"OSV returned an unsafe advisory ID: {advisory_id!r}"
                )
            records.append(vulnerability)
        raw_page_token = payload.get("next_page_token")
        if raw_page_token is None or raw_page_token == "":
            return records
        if not isinstance(raw_page_token, str) or len(raw_page_token) > 4096:
            raise urllib.error.URLError("OSV returned an invalid page token")
        page_token = raw_page_token

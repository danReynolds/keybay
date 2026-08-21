#!/usr/bin/env python3
"""Find new Apple, Android, and Linux credential-platform advisories."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

from watchers import osv

CONFIG_PATH = pathlib.Path(__file__).with_name("config.json")
_ANDROID_PATH = re.compile(r"^/docs/security/bulletin/(\d{4}-\d{2}-\d{2})$")
_APPLE_URL = re.compile(r"^https://support\.apple\.com/en-us/(\d{5,9})$")
_CVE = re.compile(r"^CVE-\d{4}-\d{4,}$")
_SAFE_SUBJECT = re.compile(r"^[^\r\n@`]{1,200}$")


def _timestamp(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp has no timezone: {value!r}")
    return parsed.astimezone(dt.timezone.utc)


def _fetch_text(url: str) -> str:
    request = urllib.request.Request(
        url, headers={"User-Agent": "keybay-security-watchers/1"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise urllib.error.URLError(f"non-UTF-8 response from {url}") from error


class _TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[dict[str, object]]] = []
        self._row: list[dict[str, object]] | None = None
        self._cell: dict[str, object] | None = None

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag == "tr":
            self._row = []
        elif tag == "td" and self._row is not None:
            self._cell = {"text": [], "links": []}
        elif tag == "a" and self._cell is not None:
            href = dict(attrs).get("href")
            if isinstance(href, str):
                links = self._cell["links"]
                assert isinstance(links, list)
                links.append(href)

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            text = self._cell["text"]
            assert isinstance(text, list)
            text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "td" and self._row is not None and self._cell is not None:
            text = self._cell["text"]
            assert isinstance(text, list)
            self._cell["text"] = " ".join("".join(text).split())
            self._row.append(self._cell)
            self._cell = None
        elif tag == "tr" and self._row is not None:
            if self._row:
                self.rows.append(self._row)
            self._row = None
            self._cell = None


class _LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag != "a":
            return
        href = dict(attrs).get("href")
        if isinstance(href, str):
            self.links.append(href)


def apple_findings(
    html: str, *, started_at: dt.datetime, products: list[str]
) -> list[dict[str, object]]:
    parser = _TableParser()
    parser.feed(html)
    grouped: dict[dt.date, list[tuple[str, str]]] = {}
    for row in parser.rows:
        if len(row) != 3:
            continue
        name = row[0]["text"]
        date_text = row[2]["text"]
        links = row[0]["links"]
        if not isinstance(name, str) or not isinstance(date_text, str):
            continue
        if not any(product in name for product in products):
            continue
        try:
            release_date = dt.datetime.strptime(date_text, "%d %b %Y").date()
        except ValueError as error:
            raise ValueError(f"unrecognized Apple release date: {date_text!r}") from error
        if release_date < started_at.date():
            continue
        if not isinstance(links, list):
            raise ValueError("Apple release links were not a list")
        official = [link for link in links if isinstance(link, str) and _APPLE_URL.fullmatch(link)]
        if not official:
            # Apple explicitly lists releases with no published CVE entry but
            # gives them no advisory link. They are updates, not actionable
            # advisory input for this watcher.
            continue
        if not _SAFE_SUBJECT.fullmatch(name):
            raise ValueError(f"unsafe Apple release title: {name!r}")
        grouped.setdefault(release_date, []).append((name, official[0]))
    if not parser.rows:
        raise ValueError("Apple security table had no rows")

    findings: list[dict[str, object]] = []
    for release_date, entries in sorted(grouped.items()):
        entries = sorted(set(entries))
        article_ids = [str(_APPLE_URL.fullmatch(url).group(1)) for _, url in entries]
        digest = hashlib.sha256("\n".join(article_ids).encode()).hexdigest()[:12]
        findings.append(
            {
                "watcher": "platforms",
                "marker": f"keybay-platform-apple-{release_date.isoformat()}-{digest}",
                "title": f"Apple platform advisory triage: {release_date.isoformat()}",
                "subjects": [name for name, _ in entries],
                "references": [
                    {"label": name, "url": url} for name, url in entries
                ],
            }
        )
    return findings


def android_findings(
    html: str, *, index_url: str, started_at: dt.datetime
) -> list[dict[str, object]]:
    parser = _LinkParser()
    parser.feed(html)
    dates: set[dt.date] = set()
    for href in parser.links:
        absolute = urllib.parse.urljoin(index_url, href)
        parsed = urllib.parse.urlparse(absolute)
        if parsed.scheme != "https" or parsed.netloc != "source.android.com":
            continue
        match = _ANDROID_PATH.fullmatch(parsed.path)
        if not match:
            continue
        bulletin_date = dt.date.fromisoformat(match.group(1))
        if bulletin_date >= started_at.date():
            dates.add(bulletin_date)
    if not any(_ANDROID_PATH.fullmatch(urllib.parse.urlparse(urllib.parse.urljoin(index_url, href)).path) for href in parser.links):
        raise ValueError("Android bulletin index had no bulletin links")
    return [
        {
            "watcher": "platforms",
            "marker": f"keybay-platform-android-{bulletin_date.isoformat()}",
            "title": f"Android platform advisory triage: {bulletin_date.isoformat()}",
            "subjects": [f"Android Security Bulletin {bulletin_date.isoformat()}"],
            "references": [
                {
                    "label": f"Android Security Bulletin {bulletin_date.isoformat()}",
                    "url": f"https://source.android.com/docs/security/bulletin/{bulletin_date.isoformat()}",
                }
            ],
        }
        for bulletin_date in sorted(dates)
    ]


def _record_time(record: dict[str, object]) -> dt.datetime:
    values = [record.get("published"), record.get("modified")]
    parsed = [_timestamp(value) for value in values if isinstance(value, str)]
    if not parsed:
        raise ValueError(f"OSV record {record.get('id')!r} had no timestamp")
    return max(parsed)


def _canonical_linux_id(record: dict[str, object]) -> str:
    candidates: list[str] = []
    for field in ("aliases", "upstream"):
        values = record.get(field) or []
        if not isinstance(values, list):
            raise ValueError(f"OSV {field} was not a list")
        candidates.extend(value for value in values if isinstance(value, str))
    cves = sorted(value for value in candidates if _CVE.fullmatch(value))
    return cves[0] if cves else str(record["id"])


def linux_findings(
    *, started_at: dt.datetime, ecosystems: list[str], packages: list[str]
) -> list[dict[str, object]]:
    grouped: dict[str, dict[str, set[str]]] = {}
    for ecosystem in ecosystems:
        for package in packages:
            for record in osv.query_package(ecosystem, package):
                if _record_time(record) < started_at:
                    continue
                canonical = _canonical_linux_id(record)
                group = grouped.setdefault(
                    canonical, {"records": set(), "subjects": set()}
                )
                group["records"].add(str(record["id"]))
                group["subjects"].add(f"{ecosystem}/{package}")
    findings: list[dict[str, object]] = []
    for canonical, group in sorted(grouped.items()):
        records = sorted(group["records"])
        findings.append(
            {
                "watcher": "platforms",
                "marker": f"keybay-platform-linux-{canonical}",
                "title": f"Linux credential-platform advisory triage: {canonical}",
                "subjects": sorted(group["subjects"]),
                "references": [
                    {
                        "label": record_id,
                        "url": f"https://osv.dev/vulnerability/{record_id}",
                    }
                    for record_id in records
                ],
            }
        )
    return findings


def findings(config: dict[str, object]) -> list[dict[str, object]]:
    started_at = _timestamp(str(config["started_at"]))
    apple = config["apple"]
    android = config["android"]
    linux = config["linux"]
    if not all(isinstance(value, dict) for value in (apple, android, linux)):
        raise ValueError("platform source definitions must be objects")
    assert isinstance(apple, dict)
    assert isinstance(android, dict)
    assert isinstance(linux, dict)
    apple_index = apple.get("index")
    android_index = android.get("index")
    products = apple.get("products")
    ecosystems = linux.get("ecosystems")
    packages = linux.get("packages")
    if apple_index != "https://support.apple.com/en-us/100100":
        raise ValueError("unexpected Apple security index")
    if android_index != "https://source.android.com/docs/security/bulletin":
        raise ValueError("unexpected Android bulletin index")
    if not all(
        isinstance(value, list) and all(isinstance(item, str) for item in value)
        for value in (products, ecosystems, packages)
    ):
        raise ValueError("platform product/package definitions must be string lists")
    assert isinstance(products, list)
    assert isinstance(ecosystems, list)
    assert isinstance(packages, list)
    return sorted(
        apple_findings(
            _fetch_text(apple_index), started_at=started_at, products=products
        )
        + android_findings(
            _fetch_text(android_index),
            index_url=android_index,
            started_at=started_at,
        )
        + linux_findings(
            started_at=started_at,
            ecosystems=ecosystems,
            packages=packages,
        ),
        key=lambda item: str(item["marker"]),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit issue-ready JSON and return 0 when every source was reachable",
    )
    args = parser.parse_args(argv)
    try:
        config = json.loads(CONFIG_PATH.read_text())
        found = findings(config)
    except (
        KeyError,
        OSError,
        ValueError,
        json.JSONDecodeError,
        urllib.error.URLError,
        TimeoutError,
    ) as error:
        print(f"platform-advisories: source or configuration invalid: {error}", file=sys.stderr)
        return 69
    if args.json:
        json.dump(found, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if not found:
        print("platform-advisories: no new Apple, Android, or Linux advisories")
        return 0
    for finding in found:
        print(f"platform-advisories: NEW: {finding['title']}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

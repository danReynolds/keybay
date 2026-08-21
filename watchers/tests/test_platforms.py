import datetime as dt
import unittest
from unittest import mock

from watchers.platforms import watch


START = dt.datetime(2026, 8, 21, tzinfo=dt.timezone.utc)


class PlatformWatcherTest(unittest.TestCase):
    def test_apple_groups_supported_releases_by_date(self):
        html = """
        <table><tr><td><a href="https://support.apple.com/en-us/123456">iOS 27.0</a></td><td>iPhone</td><td>01 Sep 2026</td></tr>
        <tr><td><a href="https://support.apple.com/en-us/123457">macOS 27.0</a></td><td>Mac</td><td>01 Sep 2026</td></tr>
        <tr><td><a href="https://support.apple.com/en-us/123458">watchOS 27.0</a></td><td>Watch</td><td>01 Sep 2026</td></tr></table>
        """
        found = watch.apple_findings(
            html,
            started_at=START,
            products=["iOS", "iPadOS", "macOS", "Background Security Improvements"],
        )
        self.assertEqual(len(found), 1)
        self.assertEqual(
            found[0]["subjects"], ["iOS 27.0", "macOS 27.0"]
        )

    def test_android_finds_only_new_bulletins(self):
        html = """
        <a href="/docs/security/bulletin/2026-08-01">August</a>
        <a href="/docs/security/bulletin/2026-09-01">September</a>
        """
        found = watch.android_findings(
            html,
            index_url="https://source.android.com/docs/security/bulletin",
            started_at=START,
        )
        self.assertEqual(
            [item["marker"] for item in found],
            ["keybay-platform-android-2026-09-01"],
        )

    def test_linux_deduplicates_distro_records_by_cve(self):
        ubuntu = {
            "id": "UBUNTU-CVE-2026-12345",
            "published": "2026-09-01T00:00:00Z",
            "aliases": ["CVE-2026-12345"],
        }
        debian = {
            "id": "DEBIAN-CVE-2026-12345",
            "modified": "2026-09-02T00:00:00Z",
            "aliases": ["CVE-2026-12345"],
        }

        def query(ecosystem: str, package: str):
            if package != "gnome-keyring":
                return []
            return [ubuntu if ecosystem == "Ubuntu" else debian]

        with mock.patch.object(watch.osv, "query_package", side_effect=query):
            found = watch.linux_findings(
                started_at=START,
                ecosystems=["Ubuntu", "Debian"],
                packages=["gnome-keyring"],
            )
        self.assertEqual(len(found), 1)
        self.assertEqual(
            found[0]["marker"], "keybay-platform-linux-CVE-2026-12345"
        )
        self.assertEqual(
            found[0]["subjects"],
            ["Debian/gnome-keyring", "Ubuntu/gnome-keyring"],
        )


if __name__ == "__main__":
    unittest.main()

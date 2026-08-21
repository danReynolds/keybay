import unittest
from unittest import mock

from watchers.critical import watch


class CriticalWatcherTest(unittest.TestCase):
    def test_reviewed_version_is_quiet(self):
        config = {
            "packages": [
                {
                    "ecosystem": "Pub",
                    "name": "cryptography",
                    "reviewed_version": "2.9.0",
                    "url": "https://pub.dev/packages/cryptography",
                }
            ]
        }
        with mock.patch.object(watch, "pub_latest", return_value="2.9.0"):
            self.assertEqual(watch.findings(config), [])

    def test_new_version_is_issue_ready(self):
        config = {
            "packages": [
                {
                    "ecosystem": "Pub",
                    "name": "cryptography",
                    "reviewed_version": "2.9.0",
                    "url": "https://pub.dev/packages/cryptography",
                }
            ]
        }
        with mock.patch.object(watch, "pub_latest", return_value="2.10.0+1"):
            found = watch.findings(config)
        self.assertEqual(len(found), 1)
        self.assertEqual(
            found[0]["marker"], "keybay-critical-pub-cryptography-2.10.0-1"
        )


if __name__ == "__main__":
    unittest.main()

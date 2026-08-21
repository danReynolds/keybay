#!/usr/bin/env python3
import unittest
from unittest import mock

from watchers.peers import watch


class PeerAdvisoriesTest(unittest.TestCase):
    def test_baseline_ids_are_suppressed(self):
        with mock.patch.object(
            watch,
            "advisories",
            return_value={"OLD-1"},
        ):
            self.assertEqual(watch.new_advisories({"OLD-1"}), {})

    def test_new_id_groups_every_affected_peer(self):
        def found(ecosystem: str, name: str) -> set[str]:
            if name in {"keyring", "keytar"}:
                return {"CVE-2026-1234"}
            return set()

        with mock.patch.object(watch, "advisories", side_effect=found):
            new = watch.new_advisories(set())

        self.assertEqual(
            new,
            {"CVE-2026-1234": ["PyPI/keyring", "crates.io/keyring", "npm/keytar"]},
        )


if __name__ == "__main__":
    unittest.main()

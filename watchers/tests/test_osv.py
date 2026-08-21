import io
import json
import unittest
from unittest import mock

from watchers import osv


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class OsvClientTest(unittest.TestCase):
    def test_paginates_and_validates_ids(self):
        responses = [
            _Response(json.dumps({"vulns": [{"id": "ONE-1"}], "next_page_token": "next"}).encode()),
            _Response(json.dumps({"vulns": [{"id": "TWO-2"}]}).encode()),
        ]
        with mock.patch.object(osv.urllib.request, "urlopen", side_effect=responses):
            found = osv.query_package("Pub", "example")
        self.assertEqual([item["id"] for item in found], ["ONE-1", "TWO-2"])


if __name__ == "__main__":
    unittest.main()

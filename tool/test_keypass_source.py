#!/usr/bin/env python3
"""The hosted-source gate rejects changed, missing, injected and linked inputs."""
import hashlib
from pathlib import Path
import tempfile
import unittest

from verify_keypass_source import verify


class SourceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="keybay-source-test-")
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name)
        files = {"LICENSE": b"license", "pubspec.yaml": b"name: keypass",
                 "native/hardware/CMakeLists.txt": b"build",
                 "native/hardware/adapter.cpp": b"source"}
        self.manifest = {"files": {name: hashlib.sha256(data).hexdigest()
                                   for name, data in files.items()}}
        for name, data in files.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

    def test_hosted_source_needs_no_git_checkout(self):
        verify(self.source, self.manifest)

    def test_changed_bytes(self):
        (self.source / "native/hardware/adapter.cpp").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)

    def test_missing_input(self):
        (self.source / "LICENSE").unlink()
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)

    def test_injected_input(self):
        (self.source / "native/hardware/extra.cmake").write_text("extra")
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)

    def test_linked_file_with_matching_bytes(self):
        target = self.source / "LICENSE"
        target.rename(self.source / "other-license")
        target.symlink_to("other-license")
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)

    def test_linked_directory_with_matching_bytes(self):
        native = self.source / "native"
        native.rename(self.source / "other-native")
        native.symlink_to("other-native", target_is_directory=True)
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)


if __name__ == "__main__":
    unittest.main()

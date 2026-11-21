import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_release", Path(__file__).with_name("verify-auralis-release.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VerifyReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.files = [Path(self.temp.name) / "installer.exe", Path(self.temp.name) / "extension.zip"]
        for index, path in enumerate(self.files):
            path.write_bytes(f"artifact {index}".encode())
        self.release = {"draft": True, "tag_name": "v1.2.3", "target_commitish": "abc123", "assets": [
            {"name": path.name, "state": "uploaded", "size": path.stat().st_size,
             "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in self.files
        ]}

    def tearDown(self):
        self.temp.cleanup()

    def check(self):
        module.verify(self.release, "1.2.3", "abc123", self.files)

    def test_matching_draft(self):
        self.check()

    def test_wrong_commit_is_rejected(self):
        self.release["target_commitish"] = "other"
        with self.assertRaisesRegex(ValueError, "target"):
            self.check()

    def test_missing_digest_is_rejected(self):
        self.release["assets"][0]["digest"] = None
        with self.assertRaisesRegex(ValueError, "digest"):
            self.check()

    def test_corrupt_or_unexpected_assets_are_rejected(self):
        self.release["assets"][0]["size"] += 1
        with self.assertRaisesRegex(ValueError, "size"):
            self.check()
        self.release["assets"].append(self.release["assets"][0])
        with self.assertRaisesRegex(ValueError, "names"):
            self.check()

    def test_published_release_is_rejected(self):
        self.release["draft"] = False
        with self.assertRaisesRegex(ValueError, "draft"):
            self.check()


if __name__ == "__main__":
    unittest.main()

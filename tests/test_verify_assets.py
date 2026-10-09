import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "Lycorine/Bundled/Cryptex/scripts/verify_assets.py"
spec = importlib.util.spec_from_file_location("verify_assets", MODULE)
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


class CryptexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bundle = self.root / "example.cxbd"
        self.restore = self.bundle / "Restore"
        self.restore.mkdir(parents=True)
        self.payload = self.restore / "test.gtcd"
        self.payload.write_bytes(b"test cryptex trust cache")
        identity = {"Info": {"Variant": "research"}, "Manifest": {
            "Cryptex1,GenericTrustCache": {"Info": {"Path": "test.gtcd"},
                                           "Digest": hashlib.sha384(self.payload.read_bytes()).digest()}}}
        (self.restore / "BuildManifest.plist").write_bytes(plistlib.dumps({"BuildIdentities": [identity]}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_good_digest(self):
        result = v.analyze(self.root, "research", False)
        self.assertEqual(len(result["assets"]), 1)
        self.assertFalse(result["has_ticket_file"])

    def test_modified_digest_rejected(self):
        self.payload.write_bytes(b"corrupted")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            v.analyze(self.root, "research", False)

    def test_missing_signature_rejected(self):
        with self.assertRaisesRegex(ValueError, "im4m"):
            v.analyze(self.root, "research", True)

    def test_ticket_presence_not_signature_validation(self):
        (self.bundle / "im4m").write_bytes(b"dummy data")
        result = v.analyze(self.root, "research", True)
        self.assertIn("NOT signature validation", result["validation"])

    def test_manifest_path_escape_rejected(self):
        data = plistlib.loads((self.restore / "BuildManifest.plist").read_bytes())
        data["BuildIdentities"][0]["Manifest"]["Cryptex1,GenericTrustCache"]["Info"]["Path"] = "../../oops"
        (self.restore / "BuildManifest.plist").write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(ValueError, "unsafe"):
            v.analyze(self.root, "research", False)


if __name__ == "__main__":
    unittest.main()

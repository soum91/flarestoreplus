import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from make_feed import make_feed, validate_download_url


class FeedTests(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": "com.Flare.FlareStore-iOS",
            "CFBundleShortVersionString": "1.5.0",
            "CFBundleVersion": "57",
            "MinimumOSVersion": "16.0",
        }

    def test_release_matches_actual_bundle_version_and_size(self):
        url = "https://downloads.example.test/releases/FlareStorePlus-b57.ipa"
        feed = make_feed(self.info, 12345678, url, "2026-11-01")
        app = feed["apps"][0]
        entry = app["versions"][0]
        self.assertEqual(entry["version"], "1.5.0")
        self.assertEqual(entry["buildVersion"], "57")
        self.assertEqual(entry["size"], 12345678)
        self.assertEqual(entry["downloadURL"], url)
        self.assertEqual(app["bundleIdentifier"], self.info["CFBundleIdentifier"])

    def test_refuses_old_build(self):
        self.info["CFBundleVersion"] = "56"
        with self.assertRaises(ValueError):
            make_feed(self.info, 1, "https://download.test/b57.ipa", "2026-11-01")

    def test_refuses_placeholder_and_wrong_protocol(self):
        for url in (
            "https://example.com/app.ipa",
            "http://download.test/app.ipa",
            "https://download.test/page",
            "https://user:password@download.test/app.ipa",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_download_url(url)


if __name__ == "__main__":
    unittest.main()

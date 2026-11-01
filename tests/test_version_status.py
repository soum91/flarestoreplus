import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from version_status import Decision, InstalledApp, InstallRecord, update_decision


class UpdateStatusTests(unittest.TestCase):
    def decide(self, latest, build=None, *, record_version="1.5.0", record_build="54", release=None,
               installed=True, confirmed=True, signed_id="com.example.signed"):
        apps = {signed_id: InstalledApp(signed_id, record_version, record_build)} if installed else {}
        ledger = [InstallRecord("com.example.original", signed_id, record_version, record_build,
                                "release-54", confirmed)]
        return update_decision("com.example.original", latest, build, apps, ledger, release)

    def test_updated_app_no_longer_shows_update(self):
        self.assertEqual(self.decide("1.5.0", "54"), Decision.CURRENT)

    def test_newer_version_detected(self):
        self.assertEqual(self.decide("1.10", record_version="1.9"), Decision.UPDATE)

    def test_build_updates_detected(self):
        self.assertEqual(self.decide("1.5.0", "55"), Decision.UPDATE)

    def test_source_identity_survives_bundle_id_change(self):
        self.assertEqual(self.decide("1.5.0", "54", signed_id="com.team.rewritten"), Decision.CURRENT)

    def test_stale_install_record_is_not_an_install(self):
        self.assertEqual(self.decide("1.5.0", "56", installed=False), Decision.INSTALL)

    def test_unconfirmed_stage_is_not_an_install(self):
        self.assertEqual(self.decide("1.5.0", "56", confirmed=False), Decision.INSTALL)

    def test_same_release_id_suppresses_false_update(self):
        self.assertEqual(self.decide("1.5.0", "999", release="release-54"), Decision.CURRENT)

    def test_unparseable_version_is_unknown(self):
        self.assertEqual(self.decide("banana"), Decision.UNKNOWN)

    def test_older_feed_version_not_an_update(self):
        self.assertEqual(self.decide("1.4.9"), Decision.CURRENT)

    def test_outside_upgrade_overrides_stale_ledger(self):
        app = InstalledApp("com.team.signed", "1.9.0", "93")
        ledger = [InstallRecord("com.example.original", "com.team.signed", "1.4.0", "40",
                                "release-old", True)]
        self.assertEqual(update_decision("com.example.original", "1.8.0", "80",
                         {app.bundle_id: app}, ledger), Decision.CURRENT)

    def test_outside_downgrade_is_detected_even_if_release_id_matches(self):
        app = InstalledApp("com.team.signed", "1.0.0", "10")
        ledger = [InstallRecord("com.example.original", "com.team.signed", "1.5.0", "56",
                                "release-56", True)]
        self.assertEqual(update_decision("com.example.original", "1.5.0", "56",
                         {app.bundle_id: app}, ledger, "release-56"), Decision.UPDATE)


if __name__ == "__main__":
    unittest.main()

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ota_evidence import summarize_ota_attempts


class OtaEvidenceTests(unittest.TestCase):
    def test_complete_download_is_not_install_confirmation(self):
        log = '''
2026-11-01 20:05:53.924  INFO  INSTALL  ───── Local install ─────
2026-11-01 20:05:53.924  INFO  INSTALL  App: Drift, dev.example.drift 0.1.0
2026-11-01 20:05:54.663  INFO  INSTALL  Manifest fetch: HTTP 200, 1850 bytes
2026-11-01 20:05:55.192  INFO  INSTALL  Handed off to iOS, installd is now fetching the manifest
2026-11-01 20:05:56.785  INFO  INSTALL  Delivered Drift.ipa to 127.0.0.1:64543: 263770 of 263770 bytes in 0.0 s
'''
        items = summarize_ota_attempts(log)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].app_name, 'Drift')
        self.assertTrue(items[0].manifest_ok)
        self.assertTrue(items[0].os_handoff)
        self.assertTrue(items[0].ipa_delivered)
        self.assertFalse(items[0].app_reported_update)
        self.assertEqual(items[0].status, 'delivered_not_confirmed')

    def test_app_reported_update_is_distinct(self):
        log = '''
2026-11-01 13:52:57.808  INFO  INSTALL  ───── Local install ─────
2026-11-01 13:52:57.808  INFO  INSTALL  App: FlareStore, com.example.flare 1.5.0
2026-11-01 13:53:01.883  INFO  INSTALL  Delivered Flare.ipa to 127.0.0.1:62900: 15133998 of 15133998 bytes in 0.0 s
2026-11-01 13:53:03.720  INFO  INSTALL  FlareStore updated in place (was 1.5.0)
'''
        item = summarize_ota_attempts(log)[0]
        self.assertTrue(item.app_reported_update)
        self.assertEqual(item.status, 'app_reported_update')

    def test_incomplete_transfer_not_a_success(self):
        log = '''
2026-11-01 00:00:00.000  INFO  INSTALL  ───── Local install ─────
2026-11-01 00:00:00.001  INFO  INSTALL  App: Example, dev.example.app 1.0
2026-11-01 00:00:00.002  INFO  INSTALL  Delivered Example.ipa to 127.0.0.1:15: 100 of 500 bytes in 0.0 s
'''
        item = summarize_ota_attempts(log)[0]
        self.assertFalse(item.ipa_delivered)
        self.assertEqual(item.status, 'started')

    def test_signing_replaced_log_does_not_count_as_install(self):
        log = '''
2026-11-01 00:00:00.000  INFO  SIGNING  Replaced Example 1.0 with the build just signed
2026-11-01 00:00:01.000  INFO  INSTALL  ───── Local install ─────
2026-11-01 00:00:01.001  INFO  INSTALL  App: Example, dev.example.app 1.0
2026-11-01 00:00:02.001  INFO  INSTALL  Opening itms-services URL
'''
        item = summarize_ota_attempts(log)[0]
        self.assertFalse(item.app_reported_update)
        self.assertFalse(item.ipa_delivered)

    def test_multiple_attempts_are_isolated(self):
        log = '''
2026-11-01 00:00:00.000  INFO  INSTALL  ───── Local install ─────
2026-11-01 00:00:00.001  INFO  INSTALL  App: Example, dev.example.app 1.0
2026-11-01 00:00:00.002  INFO  INSTALL  Delivered Example.ipa to 127.0.0.1:15: 500 of 500 bytes in 0.0 s
2026-11-01 00:01:00.000  INFO  INSTALL  ───── Local install ─────
2026-11-01 00:01:00.001  INFO  INSTALL  App: Another, dev.example.another 1.0
'''
        a, b = summarize_ota_attempts(log)
        self.assertEqual((a.status, b.status), ('delivered_not_confirmed', 'started'))


if __name__ == '__main__':
    unittest.main()

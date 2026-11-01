import asyncio
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from direct_install import DeviceApp, InstallationRejected, SignedPackage, install_and_confirm


PACKAGE = SignedPackage(
    ipa_path="/tmp/signed.ipa",
    original_bundle_id="com.example.app",
    installed_bundle_id="com.team.app",
    version="1.5.0",
    build="56",
    team_id="TEAM1",
    source_release_id="release-56",
)


class Backend:
    def __init__(self):
        self.existing = None
        self.observed = DeviceApp("com.team.app", "1.5.0", "56", "TEAM1")
        self.steps = []
        self.fail_at = None

    async def ensure_paired_tunnel(self):
        self.steps.append("pair")
        if self.fail_at == "pair":
            raise InstallationRejected("No pairing record")

    async def installed_app(self, bundle_id):
        self.steps.append("query")
        return self.existing if self.steps.count("query") == 1 else self.observed

    async def stage_via_afc(self, path):
        self.steps.append("stage")
        return "PublicStaging/signed.ipa"

    async def install_via_proxy(self, path):
        self.steps.append("install")
        if self.fail_at == "install":
            raise InstallationRejected("installation_proxy refused the package")

    async def wait_for_install_completion(self, bundle_id):
        self.steps.append("wait")
        if self.fail_at == "wait":
            raise TimeoutError("installation_proxy did not confirm completion")


class Ledger:
    def __init__(self):
        self.items = []

    def record_completed(self, package):
        self.items.append(package)


class DirectInstallationTests(unittest.TestCase):
    def test_stages_installs_verifies_then_records(self):
        backend, ledger = Backend(), Ledger()
        result = asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(result.build, "56")
        self.assertEqual(backend.steps, ["pair", "query", "stage", "install", "wait", "query"])
        self.assertEqual(ledger.items, [PACKAGE])

    def test_pairing_failure_does_not_start_install(self):
        backend, ledger = Backend(), Ledger()
        backend.fail_at = "pair"
        with self.assertRaises(InstallationRejected):
            asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(backend.steps, ["pair"])
        self.assertEqual(ledger.items, [])

    def test_failed_install_does_not_mutate_ledger(self):
        backend, ledger = Backend(), Ledger()
        backend.fail_at = "install"
        with self.assertRaises(InstallationRejected):
            asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(ledger.items, [])

    def test_missing_completion_does_not_mutate_ledger(self):
        backend, ledger = Backend(), Ledger()
        backend.fail_at = "wait"
        with self.assertRaises(TimeoutError):
            asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(ledger.items, [])

    def test_wrong_installed_version_does_not_mutate_ledger(self):
        backend, ledger = Backend(), Ledger()
        backend.observed = DeviceApp("com.team.app", "1.4.0", "42", "TEAM1")
        with self.assertRaises(InstallationRejected):
            asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(ledger.items, [])

    def test_mismatched_team_preserves_app_data(self):
        backend, ledger = Backend(), Ledger()
        backend.existing = DeviceApp("com.team.app", "1.5.0", "55", "OTHER")
        with self.assertRaises(InstallationRejected):
            asyncio.run(install_and_confirm(PACKAGE, backend, ledger))
        self.assertEqual(backend.steps, ["pair", "query"])
        self.assertEqual(ledger.items, [])


if __name__ == "__main__":
    unittest.main()

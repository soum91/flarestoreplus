from pathlib import Path
import tempfile
import unittest

from library_upgrade import apply_library_upgrade, REFRESH_IDENTIFIER


class LibraryUpgradeTests(unittest.TestCase):
    def test_refresh_and_comparison_are_in_actual_swift_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            feather = Path(directory) / "upstream/Feather"
            originals = {
                "Backend/Observable/UpdateManager.swift": '''import CoreData
@Published private(set) var lastCheckedDate: Date?
\t\tdefer {
\t\t\tisChecking = false
\t\t\tlastCheckedDate = Date()
\t\t}
\t\tlet repositories = await _fetchRepositories(from: sources)
\t\tupdates = _findUpdates(repositories: repositories, localApps: localApps)
\t\t\t\tguard remoteVersion != sourceAppVersion else {
\tprivate func _matchesStoredRepository(
''',
                "Views/Library/LibraryView.swift": '''\t@State private var _isUpdateCheckCompleteVisible = false
\t\t\tNBListAdaptable {
\t\t\t.searchable(text: $_searchText, placement: .platform())
\t\t\t.onChange(of: updateManager.isChecking) { isChecking in
\tprivate func _checkForUpdates() async {
''',
                "FeatherApp.swift": '''import OSLog
\t\tEmberAutoRefreshManager.shared.configure()
\t\treturn true
''',
                "Resources/Info.plist": '''<array>
\t\t<string>$(PRODUCT_BUNDLE_IDENTIFIER).userTask.*</string>
\t\t<string>audio</string>
</array>
''',
            }
            for relative, source in originals.items():
                path = feather / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            apply_library_upgrade(Path(directory))
            manager = (feather / "Backend/Observable/UpdateManager.swift").read_text()
            library = (feather / "Views/Library/LibraryView.swift").read_text()
            app = (feather / "FeatherApp.swift").read_text()
            plist = (feather / "Resources/Info.plist").read_text()
            background = (feather / "Ember/FlareStoreBackgroundRefresh.swift").read_text()
            self.assertIn("_isNewer(remoteVersion, than:", manager)
            self.assertIn("lexicographicallyPrecedes", manager)
            self.assertIn("FlareStorePlus.lastLibraryRefresh", manager)
            self.assertIn("refreshFromStorage()", manager)
            self.assertIn('Text("Last refreshed")', library)
            self.assertIn('Toggle("Background update checks"', library)
            self.assertIn(".refreshable { await _checkForUpdates() }", library)
            self.assertIn("FlareStoreBackgroundRefresh.register()", app)
            self.assertIn(REFRESH_IDENTIFIER, plist)
            self.assertIn("<string>fetch</string>", plist)
            self.assertIn("BGTaskScheduler.shared.register", background)

    def test_strict_upstream_change_fails_instead_of_silent_skip(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                apply_library_upgrade(Path(directory))


if __name__ == "__main__":
    unittest.main()

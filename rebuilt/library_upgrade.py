"""Apply FlareStorePlus library/update changes to the pinned Swift build.

The upstream source is kept intact in its separate repository. Strict anchors
make an upstream change fail the build instead of silently dropping a feature.
"""

from pathlib import Path


REFRESH_IDENTIFIER = "com.soum91.flarestoreplus.refresh"


def replace_once(path: Path, before: str, after: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(before) != 1:
        raise RuntimeError(f"Expected exactly one library integration anchor in {path}: {before[:90]!r}")
    path.write_text(source.replace(before, after, 1), encoding="utf-8")


def apply_library_upgrade(engine: Path) -> None:
    feather = engine / "upstream/Feather"
    library = feather / "Views/Library/LibraryView.swift"
    manager = feather / "Backend/Observable/UpdateManager.swift"
    app = feather / "FeatherApp.swift"
    plist = feather / "Resources/Info.plist"

    replace_once(manager,
        '@Published private(set) var lastCheckedDate: Date?',
        '@Published private(set) var lastCheckedDate: Date? = UserDefaults.standard.object(forKey: "FlareStorePlus.lastLibraryRefresh") as? Date')
    replace_once(manager,
        '\t\tdefer {\n\t\t\tisChecking = false\n\t\t\tlastCheckedDate = Date()\n\t\t}',
        '\t\tdefer { isChecking = false }')
    replace_once(manager,
        '\t\tlet repositories = await _fetchRepositories(from: sources)\n\t\tupdates = _findUpdates(repositories: repositories, localApps: localApps)',
        '''\t\tlet repositories = await _fetchRepositories(from: sources)
\t\t// Do not mark an offline/failed refresh as successful.
\t\tguard !repositories.isEmpty || sources.isEmpty else { return }
\t\tupdates = _findUpdates(repositories: repositories, localApps: localApps)
\t\tlastCheckedDate = Date()
\t\tUserDefaults.standard.set(lastCheckedDate, forKey: "FlareStorePlus.lastLibraryRefresh")''')
    replace_once(manager,
        '\t\t\t\tguard remoteVersion != sourceAppVersion else {',
        '\t\t\t\tguard _isNewer(remoteVersion, than: sourceAppVersion ?? localApp.version) else {')
    replace_once(manager,
        '\tprivate func _matchesStoredRepository(',
        '''\t/// Compare every numeric component, including a fourth build component.
\t/// Equality and an older feed must never produce an Update badge.
\tprivate func _isNewer(_ remote: String, than local: String?) -> Bool {
\t\tguard let local else { return false }
\t\tfunc parts(_ value: String) -> [Int]? {
\t\t\tlet fields = value.trimmingCharacters(in: .whitespacesAndNewlines)
\t\t\t\t.split(separator: ".", omittingEmptySubsequences: false)
\t\t\tguard !fields.isEmpty, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\\.isNumber) }) else { return nil }
\t\t\tlet numbers = fields.compactMap { Int($0) }
\t\t\treturn numbers.count == fields.count ? numbers : nil
\t\t}
\t\tguard var left = parts(remote), var right = parts(local) else { return false }
\t\tlet count = max(left.count, right.count)
\t\tleft += Array(repeating: 0, count: count - left.count)
\t\tright += Array(repeating: 0, count: count - right.count)
\t\treturn right.lexicographicallyPrecedes(left)
\t}

\t/// BGAppRefreshTask has no SwiftUI @FetchRequest. Load from the app's
\t/// existing store on the main actor and reuse the same update checker.
\tfunc refreshFromStorage() async {
\t\tlet storage = Storage.shared
\t\tlet sourceRequest: NSFetchRequest<AltSource> = AltSource.fetchRequest()
\t\tlet signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
\t\tlet importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
\t\tlet sources = (try? storage.context.fetch(sourceRequest)) ?? []
\t\tlet signed = (try? storage.context.fetch(signedRequest)) ?? []
\t\tlet imported = (try? storage.context.fetch(importedRequest)) ?? []
\t\tlet apps: [AppInfoPresentable] = signed.map { $0 as AppInfoPresentable }
\t\t\t+ imported.map { $0 as AppInfoPresentable }
\t\tawait checkForUpdates(sources: sources, localApps: apps)
\t}

\tprivate func _matchesStoredRepository(''')

    replace_once(library,
        '\t@State private var _isUpdateCheckCompleteVisible = false',
        '''\t@State private var _isUpdateCheckCompleteVisible = false
\t@AppStorage("FlareStorePlus.backgroundRefreshEnabled") private var _backgroundRefreshEnabled = true''')
    replace_once(library,
        '\t\t\tNBListAdaptable {',
        '''\t\t\tNBListAdaptable {
\t\t\t\tSection {
\t\t\t\t\tHStack {
\t\t\t\t\t\tVStack(alignment: .leading, spacing: 4) {
\t\t\t\t\t\t\tText("Last refreshed").font(.subheadline)
\t\t\t\t\t\t\tif let date = updateManager.lastCheckedDate {
\t\t\t\t\t\t\t\tText(date.formatted(date: .abbreviated, time: .shortened))
\t\t\t\t\t\t\t\t\t.font(.caption).foregroundStyle(.secondary)
\t\t\t\t\t\t\t} else {
\t\t\t\t\t\t\t\tText("Never").font(.caption).foregroundStyle(.secondary)
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}
\t\t\t\t\t\tSpacer()
\t\t\t\t\t\tif updateManager.isChecking { ProgressView() }
\t\t\t\t\t\tButton("Refresh now") { Task { await _checkForUpdates() } }
\t\t\t\t\t\t\t.disabled(updateManager.isChecking)
\t\t\t\t\t}
\t\t\t\t\tToggle("Background update checks", isOn: $_backgroundRefreshEnabled)
\t\t\t\t\t\t.onChange(of: _backgroundRefreshEnabled) { enabled in
\t\t\t\t\t\t\tif enabled { FlareStoreBackgroundRefresh.schedule() }
\t\t\t\t\t\t\telse { FlareStoreBackgroundRefresh.cancel() }
\t\t\t\t\t\t}
\t\t\t\t} header: { Text("Updates") }''')
    replace_once(library,
        '\t\t\t.searchable(text: $_searchText, placement: .platform())',
        '''\t\t\t.refreshable { await _checkForUpdates() }
\t\t\t.searchable(text: $_searchText, placement: .platform())''')
    replace_once(library,
        '\t\t\t.onChange(of: updateManager.isChecking) { isChecking in',
        '''\t\t\t.task { await _refreshIfStale() }
\t\t\t.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
\t\t\t\tTask { await _refreshIfStale() }
\t\t\t}
\t\t\t.onChange(of: updateManager.isChecking) { isChecking in''')
    replace_once(library,
        '\tprivate func _checkForUpdates() async {',
        '''\tprivate func _refreshIfStale() async {
\t\tguard _backgroundRefreshEnabled, !updateManager.isChecking else { return }
\t\tif let last = updateManager.lastCheckedDate, Date().timeIntervalSince(last) < 900 { return }
\t\tawait _checkForUpdates()
\t}

\tprivate func _checkForUpdates() async {''')

    replace_once(app,
        'import OSLog',
        'import OSLog\nimport BackgroundTasks')
    replace_once(app,
        '\t\t_addDefaultCertificates()\n\t\treturn true',
        '\t\t_addDefaultCertificates()\n\t\tFlareStoreBackgroundRefresh.register()\n\t\tFlareStoreBackgroundRefresh.schedule()\n\t\treturn true')
    replace_once(plist,
        '\t\t<string>$(PRODUCT_BUNDLE_IDENTIFIER).userTask.*</string>',
        '\t\t<string>$(PRODUCT_BUNDLE_IDENTIFIER).userTask.*</string>\n'
        f'\t\t<string>{REFRESH_IDENTIFIER}</string>')
    replace_once(plist,
        '\t\t<string>audio</string>',
        '\t\t<string>audio</string>\n\t\t<string>fetch</string>')

    companion = feather / "Ember/FlareStoreBackgroundRefresh.swift"
    companion.parent.mkdir(parents=True, exist_ok=True)
    companion.write_text('''import Foundation
import BackgroundTasks

/// iOS schedules background refresh opportunistically; there is no fixed interval.
enum FlareStoreBackgroundRefresh {
    static let identifier = "com.soum91.flarestoreplus.refresh"
    private static let setting = "FlareStorePlus.backgroundRefreshEnabled"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let work = Task { @MainActor in
                await UpdateManager.shared.refreshFromStorage()
                refresh.setTaskCompleted(success: !Task.isCancelled)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let enabled = UserDefaults.standard.object(forKey: setting) as? Bool ?? true
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}
''', encoding="utf-8")

import Foundation

/// Host-facing bridge. The proprietary IPA must explicitly call these methods
/// from its own Update/Install actions. This is NOT an injected binary hook.
public actor InstallAftercareBridge {
    private let coordinator: InstallCoordinator
    private let installedApps: any InstalledAppQuery
    private struct Attempt: Sendable {
        let package: SignedPackage
        let before: InstalledApp?
    }
    private var pending: [String: Attempt] = [:]

    public init(coordinator: InstallCoordinator, installedApps: any InstalledAppQuery) {
        self.coordinator = coordinator
        self.installedApps = installedApps
    }

    /// Begin installation without claiming success from OTA handoff/download.
    @discardableResult
    public func installOrUpdate(_ package: SignedPackage) async throws -> InstallOutcome {
        let before = try await installedApps.installedApp(bundleID: package.effectiveBundleID)
        let result = try await coordinator.start(package)
        pending[package.effectiveBundleID] = Attempt(package: package, before: before)
        return result
    }

    /// Invoke when foreground installed-app metadata refreshes.
    /// Unchanged pre-existing metadata is not proof of a same-build OTA update.
    public func reconcileAfterForeground() async throws -> [String: InstallOutcome] {
        var outcomes: [String: InstallOutcome] = [:]
        for (bundleID, attempt) in pending {
            let current = try await installedApps.installedApp(bundleID: bundleID)
            if let before = attempt.before, before == current {
                outcomes[bundleID] = .pendingVerification
                continue
            }
            let result = try await coordinator.reconcile(attempt.package)
            outcomes[bundleID] = result
            if case .confirmed = result {
                pending.removeValue(forKey: bundleID)
            }
        }
        return outcomes
    }

    /// ONLY invoke after verified installation_proxy transaction completion.
    /// HTTP 200 and an itms-services handoff do not qualify.
    public func installerTransactionCompleted(bundleID: String) async throws -> InstallOutcome {
        guard let attempt = pending[bundleID] else { return .pendingVerification }
        let result = try await coordinator.reconcile(attempt.package)
        if case .confirmed = result { pending.removeValue(forKey: bundleID) }
        return result
    }

    public func pendingBundleIdentifiers() -> [String] { pending.keys.sorted() }
}

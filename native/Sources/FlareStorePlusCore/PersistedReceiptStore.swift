import Foundation

/// Persists only device-confirmed installs; suitable for an App Group defaults suite.
public actor PersistedReceiptStore: ReceiptStore {
    private let defaults: UserDefaults
    private let key: String
    public enum StorageError: Error { case unavailableDefaultsSuite }

    public init(suiteName: String, key: String = "flarestoreplus.confirmedReceipts.v1") throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw StorageError.unavailableDefaultsSuite
        }
        self.defaults = defaults
        self.key = key
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    public func all() throws -> [ConfirmedReceipt] {
        guard let payload = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([ConfirmedReceipt].self, from: payload)
    }

    public func append(_ receipt: ConfirmedReceipt) async throws {
        var stored = try all()
        stored.removeAll {
            $0.package.source.originalBundleID == receipt.package.source.originalBundleID &&
            $0.package.effectiveBundleID == receipt.package.effectiveBundleID
        }
        stored.append(receipt)
        defaults.set(try JSONEncoder().encode(stored), forKey: key)
    }
}
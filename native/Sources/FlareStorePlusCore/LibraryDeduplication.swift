import Foundation

/// A display-only consolidation of duplicate library entries. Never deletes files.
public struct LibraryEntry: Sendable, Equatable {
    public let originalBundleID: String
    public let effectiveBundleID: String
    public let version: String
    public let build: String
    public let recordID: String
    public let lastModified: Date
    public init(originalBundleID: String, effectiveBundleID: String, version: String,
                build: String, recordID: String, lastModified: Date) {
        self.originalBundleID = originalBundleID
        self.effectiveBundleID = effectiveBundleID
        self.version = version
        self.build = build
        self.recordID = recordID
        self.lastModified = lastModified
    }
}

public enum LibraryDeduplication {
    public static func uniqueEntries(_ input: [LibraryEntry]) -> [LibraryEntry] {
        struct Key: Hashable {
            let source: String
            let effective: String
            let version: String
            let build: String
        }
        var bestByKey: [Key: LibraryEntry] = [:]
        for entry in input {
            let key = Key(source: entry.originalBundleID, effective: entry.effectiveBundleID,
                          version: entry.version, build: entry.build)
            if let existing = bestByKey[key] {
                if entry.lastModified > existing.lastModified ||
                    (entry.lastModified == existing.lastModified && entry.recordID < existing.recordID) {
                    bestByKey[key] = entry
                }
            } else { bestByKey[key] = entry }
        }
        return bestByKey.values.sorted { $0.recordID < $1.recordID }
    }
}
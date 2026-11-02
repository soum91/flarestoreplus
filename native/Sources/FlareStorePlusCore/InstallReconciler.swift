import Foundation

/// Original repository identities differ from effective IDs after re-signing.
public struct SourceRelease: Codable, Sendable, Equatable {
    public let originalBundleID: String
    public let version: String
    public let build: String?
    public let releaseID: String?
    public init(originalBundleID: String, version: String, build: String?, releaseID: String? = nil) {
        self.originalBundleID = originalBundleID
        self.version = version
        self.build = build
        self.releaseID = releaseID
    }
}

public struct SignedPackage: Codable, Sendable, Equatable {
    public let source: SourceRelease
    public let effectiveBundleID: String
    public let signedVersion: String
    public let signedBuild: String?
    public let signingTeamID: String?
    public let localIPAPath: String
    public init(source: SourceRelease, effectiveBundleID: String, signedVersion: String,
                signedBuild: String?, signingTeamID: String?, localIPAPath: String) {
        self.source = source
        self.effectiveBundleID = effectiveBundleID
        self.signedVersion = signedVersion
        self.signedBuild = signedBuild
        self.signingTeamID = signingTeamID
        self.localIPAPath = localIPAPath
    }
}

public struct InstalledApp: Codable, Sendable, Equatable {
    public let bundleID: String
    public let version: String
    public let build: String?
    public let teamID: String?
    public init(bundleID: String, version: String, build: String?, teamID: String?) {
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.teamID = teamID
    }
}

/// Only store a receipt after a real device installation query confirms it.
public struct ConfirmedReceipt: Codable, Sendable, Equatable {
    public let package: SignedPackage
    public let installed: InstalledApp
    public let confirmedAt: Date
    public init(package: SignedPackage, installed: InstalledApp, confirmedAt: Date) {
        self.package = package
        self.installed = installed
        self.confirmedAt = confirmedAt
    }
}

public enum UpdateAction: String, Codable, Sendable, Equatable {
    case install, update, current, needsVerification
}

public enum VersionComparator {
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func parse(_ string: String) -> [Int]? {
            let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else { return nil }
            var numbers: [Int] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int(piece) else { return nil }
                numbers.append(value)
            }
            return numbers
        }
        guard let left = parse(lhs), let right = parse(rhs) else { return nil }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}

public enum UpdateReconciler {
    public static func action(for release: SourceRelease,
                              installed: [String: InstalledApp],
                              receipts: [ConfirmedReceipt]) -> UpdateAction {
        let candidates = receipts.filter { receipt in
            receipt.package.source.originalBundleID == release.originalBundleID &&
            receipt.package.effectiveBundleID == receipt.installed.bundleID &&
            installed[receipt.installed.bundleID] != nil
        }
        guard !candidates.isEmpty else { return .install }
        var best: InstalledApp?
        for receipt in candidates {
            guard let observed = installed[receipt.installed.bundleID] else { continue }
            if let existing = best {
                guard let comparison = VersionComparator.compare(observed.version, existing.version) else {
                    return .needsVerification
                }
                if comparison == .orderedDescending { best = observed }
                if comparison == .orderedSame, let a = observed.build, let b = existing.build {
                    guard let order = VersionComparator.compare(a, b) else { return .needsVerification }
                    if order == .orderedDescending { best = observed }
                }
            } else { best = observed }
        }
        guard let observed = best else { return .install }
        guard let versionOrder = VersionComparator.compare(release.version, observed.version) else {
            return .needsVerification
        }
        if versionOrder == .orderedDescending { return .update }
        if versionOrder == .orderedAscending { return .current }
        if let latestBuild = release.build, let seenBuild = observed.build {
            guard let buildOrder = VersionComparator.compare(latestBuild, seenBuild) else {
                return .needsVerification
            }
            return buildOrder == .orderedDescending ? .update : .current
        }
        return .current
    }
}

public protocol InstalledAppQuery: Sendable {
    /// Must query actual iOS installations, never the cached IPA library.
    func installedApp(bundleID: String) async throws -> InstalledApp?
}

public protocol InstallTransport: Sendable {
    /// OTA handoff or a paired-device install is not automatically completion.
    func beginInstall(package: SignedPackage) async throws
}

public protocol ReceiptStore: Sendable {
    func append(_ receipt: ConfirmedReceipt) async throws
}

public enum InstallOutcome: Sendable, Equatable {
    case pendingVerification
    case confirmed(InstalledApp)
}

public enum InstallFailure: Error, Equatable {
    case invalidPackage
    case changedSigningTeam
    case noDeviceEvidence
    case observedDifferentVersion
}

public struct InstallCoordinator: Sendable {
    public let query: any InstalledAppQuery
    public let transport: any InstallTransport
    public let receipts: any ReceiptStore
    public init(query: any InstalledAppQuery, transport: any InstallTransport, receipts: any ReceiptStore) {
        self.query = query
        self.transport = transport
        self.receipts = receipts
    }

    public func start(_ package: SignedPackage) async throws -> InstallOutcome {
        guard !package.effectiveBundleID.isEmpty, !package.localIPAPath.isEmpty,
              !package.signedVersion.isEmpty else { throw InstallFailure.invalidPackage }
        if let existing = try await query.installedApp(bundleID: package.effectiveBundleID),
           let oldTeam = existing.teamID, let newTeam = package.signingTeamID,
           oldTeam != newTeam {
            throw InstallFailure.changedSigningTeam
        }
        try await transport.beginInstall(package: package)
        return .pendingVerification
    }

    public func reconcile(_ package: SignedPackage, confirmedAt: Date = Date()) async throws -> InstallOutcome {
        guard let observed = try await query.installedApp(bundleID: package.effectiveBundleID) else {
            return .pendingVerification
        }
        guard observed.version == package.signedVersion,
              (package.signedBuild == nil || observed.build == package.signedBuild) else {
            return .pendingVerification
        }
        try await receipts.append(ConfirmedReceipt(package: package, installed: observed, confirmedAt: confirmedAt))
        return .confirmed(observed)
    }
}
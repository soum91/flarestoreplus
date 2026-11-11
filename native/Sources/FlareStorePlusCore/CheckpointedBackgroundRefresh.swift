import Foundation

/// Progress across short BGAppRefreshTask runs. The host cache remains authoritative.
public struct SourceRefreshCheckpoint: Codable, Equatable, Sendable {
    public var sourceIDs: [String]
    public var pending: [String]
    public var succeededThisCycle: [String]
    public var lastPerSourceSuccess: [String: Date]
    public var failureCounts: [String: Int]
    public var lastAttemptAt: Date?
    public var lastPartialAt: Date?
    public var lastFullAt: Date?
    public var fullSourceIDs: [String]

    public init(sourceIDs: [String] = []) {
        let unique = Self.unique(sourceIDs)
        self.sourceIDs = unique
        self.pending = unique
        self.succeededThisCycle = []
        self.lastPerSourceSuccess = [:]
        self.failureCounts = [:]
        self.lastAttemptAt = nil
        self.lastPartialAt = nil
        self.lastFullAt = nil
        self.fullSourceIDs = []
    }

    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Reconcile added/removed sources without losing partial progress.
    public mutating func reconcile(sourceIDs current: [String]) {
        let requested = Self.unique(current)
        let set = Set(requested)
        sourceIDs = requested
        succeededThisCycle = Self.unique(succeededThisCycle).filter { set.contains($0) }
        let successes = Set(succeededThisCycle)
        pending = Self.unique(pending).filter { set.contains($0) && !successes.contains($0) }
        let tracked = Set(pending).union(successes)
        let additions = requested.filter { !tracked.contains($0) }
        pending = additions + pending
        failureCounts = failureCounts.filter { set.contains($0.key) }
        lastPerSourceSuccess = lastPerSourceSuccess.filter { set.contains($0.key) }
    }

    /// Last full cycle is only current when the repository set is unchanged.
    public var currentSetFullyRefreshedAt: Date? {
        Set(sourceIDs) == Set(fullSourceIDs) ? lastFullAt : nil
    }
}

public struct RefreshBatchPolicy: Sendable, Equatable {
    public let maxSources: Int
    public let budgetSeconds: TimeInterval
    public let safetyMarginSeconds: TimeInterval

    public init(maxSources: Int = 8, budgetSeconds: TimeInterval = 18,
                safetyMarginSeconds: TimeInterval = 2) {
        self.maxSources = max(1, maxSources)
        self.budgetSeconds = max(1, budgetSeconds)
        self.safetyMarginSeconds = max(0, safetyMarginSeconds)
    }
}

public enum RefreshBatchExit: String, Codable, Equatable, Sendable {
    case complete, partial, expired, allFailed, empty
}

public struct RefreshBatchReport: Sendable, Equatable {
    public let attempted: [String]
    public let succeeded: [String]
    public let failed: [String]
    public let remaining: Int
    public let exit: RefreshBatchExit
    public let lastFullAt: Date?
    public let lastPartialAt: Date?
}

public protocol SourceRefreshBackend: Sendable {
    /// The host must respect the deadline and cancel URLSession requests.
    /// A success means the host has committed the source into its cache.
    func refreshSource(id: String, deadline: Date) async throws
}

public protocol SourceRefreshCheckpointStore: Sendable {
    func load() async throws -> SourceRefreshCheckpoint?
    func save(_ checkpoint: SourceRefreshCheckpoint) async throws
}

/// Native engine awaiting host integration; does not patch the original executable.
public actor CheckpointedBackgroundRefresher {
    private let backend: any SourceRefreshBackend
    private let store: any SourceRefreshCheckpointStore

    public init(backend: any SourceRefreshBackend, store: any SourceRefreshCheckpointStore) {
        self.backend = backend
        self.store = store
    }

    public func run(sourceIDs: [String], policy: RefreshBatchPolicy = .init(),
                    now: @Sendable () -> Date = { Date() }) async throws -> RefreshBatchReport {
        var state = try await store.load() ?? SourceRefreshCheckpoint()
        state.reconcile(sourceIDs: sourceIDs)
        state.lastAttemptAt = now()
        try await store.save(state)
        guard !state.sourceIDs.isEmpty else {
            return RefreshBatchReport(attempted: [], succeeded: [], failed: [],
                                      remaining: 0, exit: .empty,
                                      lastFullAt: state.currentSetFullyRefreshedAt,
                                      lastPartialAt: state.lastPartialAt)
        }

        let deadline = now().addingTimeInterval(policy.budgetSeconds)
        var attempted: [String] = [], successes: [String] = [], failures: [String] = []
        var expired = false
        var seenThisRun = Set<String>()
        while attempted.count < policy.maxSources {
            if Task.isCancelled || now().addingTimeInterval(policy.safetyMarginSeconds) >= deadline {
                expired = true
                break
            }
            guard let next = state.pending.first(where: { !seenThisRun.contains($0) }) else { break }
            seenThisRun.insert(next)
            attempted.append(next)
            do {
                try await backend.refreshSource(id: next, deadline: deadline)
                // Committed responses must survive subsequent cancellation.
                state.pending.removeAll(where: { $0 == next })
                if !state.succeededThisCycle.contains(next) { state.succeededThisCycle.append(next) }
                state.lastPerSourceSuccess[next] = now()
                state.failureCounts.removeValue(forKey: next)
                state.lastPartialAt = now()
                successes.append(next)
                try await store.save(state)
            } catch is CancellationError {
                expired = true
                try await store.save(state)
                break
            } catch {
                // Rotate failing sources rather than starving healthy ones.
                state.pending.removeAll(where: { $0 == next })
                state.pending.append(next)
                state.failureCounts[next, default: 0] += 1
                failures.append(next)
                try await store.save(state)
            }
        }
        let completed = state.pending.isEmpty
        if completed {
            state.lastFullAt = now()
            state.fullSourceIDs = state.sourceIDs
            state.pending = state.sourceIDs
            state.succeededThisCycle = []
            try await store.save(state)
        }
        let exit: RefreshBatchExit = completed ? .complete :
            expired ? .expired : (successes.isEmpty && !failures.isEmpty ? .allFailed : .partial)
        return RefreshBatchReport(attempted: attempted, succeeded: successes, failed: failures,
                                  remaining: completed ? 0 : state.pending.count, exit: exit,
                                  lastFullAt: state.currentSetFullyRefreshedAt,
                                  lastPartialAt: state.lastPartialAt)
    }
}

/// Use the app's private container, never the source list or signing ledger.
public actor JSONFileRefreshCheckpointStore: SourceRefreshCheckpointStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> SourceRefreshCheckpoint? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SourceRefreshCheckpoint.self, from: Data(contentsOf: url))
    }
    public func save(_ checkpoint: SourceRefreshCheckpoint) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(checkpoint)
        try payload.write(to: url, options: .atomic)
    }
}

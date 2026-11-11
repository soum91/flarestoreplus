import Foundation
import XCTest
@testable import FlareStorePlusCore

private actor MemoryCheckpointStore: SourceRefreshCheckpointStore {
    var state: SourceRefreshCheckpoint?
    var saves = 0
    func load() -> SourceRefreshCheckpoint? { state }
    func save(_ checkpoint: SourceRefreshCheckpoint) { state = checkpoint; saves += 1 }
    func snapshot() -> SourceRefreshCheckpoint? { state }
    func saveCount() -> Int { saves }
}

private actor TestSourceBackend: SourceRefreshBackend {
    var calls: [String] = []
    let fail: Set<String>
    let cancel: Set<String>
    init(fail: Set<String> = [], cancel: Set<String> = []) {
        self.fail = fail; self.cancel = cancel
    }
    func refreshSource(id: String, deadline: Date) throws {
        calls.append(id)
        if cancel.contains(id) { throw CancellationError() }
        if fail.contains(id) { throw URLError(.timedOut) }
    }
    func requested() -> [String] { calls }
}

final class CheckpointedBackgroundRefreshTests: XCTestCase {
    let ids = (1...33).map { "https://repo\($0).example/source.json" }

    func test33SourcesCompleteAcrossFiveBoundedRuns() async throws {
        let backend = TestSourceBackend(), store = MemoryCheckpointStore()
        let refresher = CheckpointedBackgroundRefresher(backend: backend, store: store)
        var batchSizes: [Int] = []
        var statuses: [RefreshBatchExit] = []
        for _ in 0..<5 {
            let report = try await refresher.run(sourceIDs: ids)
            batchSizes.append(report.attempted.count)
            statuses.append(report.exit)
        }
        XCTAssertEqual(batchSizes, [8, 8, 8, 8, 1])
        XCTAssertEqual(statuses, [.partial, .partial, .partial, .partial, .complete])
        let calls = await backend.requested()
        XCTAssertEqual(calls.count, 33)
        XCTAssertEqual(Set(calls), Set(ids))
        let value = await store.snapshot()
        let checkpoint = try XCTUnwrap(value)
        XCTAssertNotNil(checkpoint.currentSetFullyRefreshedAt)
        XCTAssertEqual(checkpoint.pending.count, 33)
        XCTAssertTrue(checkpoint.succeededThisCycle.isEmpty)
    }

    func testCancellationPreservesPreviousCompletionsAndRetriesInFlight() async throws {
        let backend = TestSourceBackend(cancel: [ids[2]])
        let store = MemoryCheckpointStore()
        let report = try await CheckpointedBackgroundRefresher(backend: backend, store: store)
            .run(sourceIDs: ids)
        XCTAssertEqual(report.exit, .expired)
        XCTAssertEqual(report.succeeded, Array(ids.prefix(2)))
        let value = await store.snapshot()
        let checkpoint = try XCTUnwrap(value)
        XCTAssertEqual(checkpoint.succeededThisCycle, Array(ids.prefix(2)))
        XCTAssertEqual(checkpoint.pending.first, ids[2])
        let count = await store.saveCount()
        XCTAssertGreaterThanOrEqual(count, 4)
    }

    func testSlowSourceCannotStarveHealthySources() async throws {
        let backend = TestSourceBackend(fail: [ids[0]])
        let store = MemoryCheckpointStore()
        let refresher = CheckpointedBackgroundRefresher(backend: backend, store: store)
        let report = try await refresher.run(sourceIDs: Array(ids.prefix(4)),
                                             policy: RefreshBatchPolicy(maxSources: 4))
        XCTAssertEqual(report.succeeded.count, 3)
        XCTAssertEqual(report.failed, [ids[0]])
        XCTAssertEqual(report.remaining, 1)
        let value = await store.snapshot()
        let checkpoint = try XCTUnwrap(value)
        XCTAssertEqual(checkpoint.pending, [ids[0]])
        XCTAssertEqual(checkpoint.failureCounts[ids[0]], 1)
        XCTAssertNil(checkpoint.currentSetFullyRefreshedAt)
    }

    func testAddedAndRemovedSourcesInvalidateCurrentSetFullStatus() async throws {
        let backend = TestSourceBackend(), store = MemoryCheckpointStore()
        let refresher = CheckpointedBackgroundRefresher(backend: backend, store: store)
        let initial = try await refresher.run(sourceIDs: [ids[0], ids[1]])
        XCTAssertEqual(initial.exit, .complete)
        let changed = try await refresher.run(sourceIDs: [ids[0], ids[1], ids[2]],
                                              policy: RefreshBatchPolicy(maxSources: 1))
        XCTAssertEqual(changed.attempted, [ids[2]])
        XCTAssertEqual(changed.exit, .partial)
        let value = await store.snapshot()
        let snapshot = try XCTUnwrap(value)
        XCTAssertEqual(Set(snapshot.fullSourceIDs), Set([ids[0], ids[1]]))
        XCTAssertNil(snapshot.currentSetFullyRefreshedAt)
        let resumed = try await refresher.run(sourceIDs: [ids[0], ids[1], ids[2]])
        XCTAssertEqual(resumed.exit, .complete)
        let final = await store.snapshot()
        XCTAssertEqual(Set(final?.fullSourceIDs ?? []), Set([ids[0], ids[1], ids[2]]))
        XCTAssertNotNil(final?.currentSetFullyRefreshedAt)
    }

    func testPersistenceAtomicRoundTripAndDistinctCacheStatus() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("progress.json")
        let store = JSONFileRefreshCheckpointStore(url: path)
        let backend = TestSourceBackend()
        let report = try await CheckpointedBackgroundRefresher(backend: backend, store: store)
            .run(sourceIDs: ids, policy: RefreshBatchPolicy(maxSources: 3))
        XCTAssertEqual(report.exit, .partial)
        XCTAssertNil(report.lastFullAt)
        XCTAssertNotNil(report.lastPartialAt)
        let data = try await JSONFileRefreshCheckpointStore(url: path).load()
        let state = try XCTUnwrap(data)
        XCTAssertEqual(state.succeededThisCycle, Array(ids.prefix(3)))
        XCTAssertNil(state.currentSetFullyRefreshedAt)
    }

    func testZeroWorkAndDuplicates() async throws {
        let backend = TestSourceBackend(), store = MemoryCheckpointStore()
        let refresher = CheckpointedBackgroundRefresher(backend: backend, store: store)
        let empty = try await refresher.run(sourceIDs: [])
        XCTAssertEqual(empty.exit, .empty)
        let report = try await refresher.run(sourceIDs: [ids[0], ids[0], "", ids[1]])
        XCTAssertEqual(report.exit, .complete)
        XCTAssertEqual(report.succeeded, [ids[0], ids[1]])
    }
}

import Foundation
import XCTest
@testable import FlareStorePlusCore

private actor FakeBackend: InstalledAppQuery, InstallTransport, ReceiptStore {
    private var apps: [String: InstalledApp] = [:]
    private(set) var started = 0
    private(set) var saved: [ConfirmedReceipt] = []
    func installedApp(bundleID: String) async throws -> InstalledApp? { apps[bundleID] }
    func beginInstall(package: SignedPackage) async throws { started += 1 }
    func append(_ receipt: ConfirmedReceipt) async throws { saved.append(receipt) }
    func set(_ app: InstalledApp) { apps[app.bundleID] = app }
    func count() -> Int { saved.count }
    func startedCount() -> Int { started }
}

final class ReconciliationTests: XCTestCase {
    let release = SourceRelease(originalBundleID: "original", version: "0.1.0", build: "9")
    func package() -> SignedPackage {
        SignedPackage(source: release, effectiveBundleID: "signed", signedVersion: "0.1.0",
                      signedBuild: "9", signingTeamID: "TEAM", localIPAPath: "/tmp/drift.ipa")
    }
    func app(_ build: String = "9", team: String = "TEAM") -> InstalledApp {
        InstalledApp(bundleID: "signed", version: "0.1.0", build: build, teamID: team)
    }

    func testOTADownloadAloneCannotCountAsInstalled() async throws {
        let fake = FakeBackend()
        let coordinator = InstallCoordinator(query: fake, transport: fake, receipts: fake)
        let outcome = try await coordinator.start(package())
        let receipts = await fake.count()
        XCTAssertEqual(outcome, .pendingVerification)
        XCTAssertEqual(receipts, 0)
    }

    func testMissingInstalledAppRemainsPending() async throws {
        let fake = FakeBackend()
        let outcome = try await InstallCoordinator(query: fake, transport: fake, receipts: fake)
            .reconcile(package())
        XCTAssertEqual(outcome, .pendingVerification)
        let count = await fake.count()
        XCTAssertEqual(count, 0)
    }

    func testWrongBuildDoesNotClearUpdate() async throws {
        let fake = FakeBackend()
        await fake.set(app("8"))
        let outcome = try await InstallCoordinator(query: fake, transport: fake, receipts: fake)
            .reconcile(package())
        XCTAssertEqual(outcome, .pendingVerification)
    }

    func testConfirmedBuildCreatesReceipt() async throws {
        let fake = FakeBackend()
        await fake.set(app())
        let outcome = try await InstallCoordinator(query: fake, transport: fake, receipts: fake)
            .reconcile(package())
        let count = await fake.count()
        XCTAssertEqual(outcome, .confirmed(app()))
        XCTAssertEqual(count, 1)
    }

    func testDifferentSigningTeamPreservesInstalledApp() async throws {
        let fake = FakeBackend()
        await fake.set(app("8", team: "OTHER"))
        do {
            _ = try await InstallCoordinator(query: fake, transport: fake, receipts: fake)
                .start(package())
            XCTFail("Expected safety rejection")
        } catch let error as InstallFailure {
            XCTAssertEqual(error, .changedSigningTeam)
            let started = await fake.startedCount()
            XCTAssertEqual(started, 0)
        }
    }

    func testVersionAndBuildReconciliation() {
        let installed = app("8")
        let receipt = ConfirmedReceipt(package: package(), installed: installed, confirmedAt: Date())
        XCTAssertEqual(UpdateReconciler.action(for: release,
                                               installed: [installed.bundleID: installed],
                                               receipts: [receipt]), .update)
        let newer = app()
        XCTAssertEqual(UpdateReconciler.action(for: release,
                                               installed: [newer.bundleID: newer],
                                               receipts: [receipt]), .current)
        XCTAssertEqual(UpdateReconciler.action(for: release,
                                               installed: [:], receipts: [receipt]), .install)
    }

    func testPersistenceReplacesStaleReceipt() async throws {
        let store = try PersistedReceiptStore(suiteName: "FSP.\(UUID().uuidString)")
        let first = ConfirmedReceipt(package: package(), installed: app("8"), confirmedAt: Date.distantPast)
        let second = ConfirmedReceipt(package: package(), installed: app(), confirmedAt: Date())
        try await store.append(first)
        try await store.append(second)
        let receipts = try await store.all()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].installed.build, "9")
        await store.clear()
    }

    func testDuplicateLibraryEntriesNotDeleted() {
        let now = Date()
        let entries = [
            LibraryEntry(originalBundleID: "original", effectiveBundleID: "signed",
                         version: "0.1.0", build: "9", recordID: "old", lastModified: now),
            LibraryEntry(originalBundleID: "original", effectiveBundleID: "signed",
                         version: "0.1.0", build: "9", recordID: "new",
                         lastModified: now.addingTimeInterval(1)),
            LibraryEntry(originalBundleID: "original", effectiveBundleID: "signed",
                         version: "0.1.0", build: "10", recordID: "different",
                         lastModified: now),
        ]
        let deduped = LibraryDeduplication.uniqueEntries(entries)
        XCTAssertEqual(deduped.count, 2)
        XCTAssertTrue(deduped.contains { $0.recordID == "new" })
    }
}

import Foundation
import XCTest
@testable import FlareStorePlusCore

private actor FakeDevice: InstalledAppQuery, InstallTransport, ReceiptStore {
    var apps: [String: InstalledApp] = [:]
    var receipts: [ConfirmedReceipt] = []
    func installedApp(bundleID: String) async throws -> InstalledApp? { apps[bundleID] }
    func beginInstall(package: SignedPackage) async throws { }
    func append(_ receipt: ConfirmedReceipt) async throws { receipts.append(receipt) }
    func set(_ app: InstalledApp) { apps[app.bundleID] = app }
    func count() -> Int { receipts.count }
}
final class AftercareBridgeTests: XCTestCase {
    func app(_ build: String) -> InstalledApp {
        InstalledApp(bundleID: "dev.signed", version: "0.1.0", build: build, teamID: "TEAM")
    }
    func pkg(_ build: String = "9") -> SignedPackage {
        SignedPackage(source: SourceRelease(originalBundleID: "dev.original", version: "0.1.0", build: build),
                      effectiveBundleID: "dev.signed", signedVersion: "0.1.0", signedBuild: build,
                      signingTeamID: "TEAM", localIPAPath: "/tmp/signed.ipa")
    }
    func bridge(_ device: FakeDevice) -> InstallAftercareBridge {
        InstallAftercareBridge(coordinator: InstallCoordinator(query: device, transport: device, receipts: device),
                               installedApps: device)
    }
    func testDownloadHandoffCannotConfirmInstallation() async throws {
        let device = FakeDevice()
        let subject = bridge(device)
        let status = try await subject.installOrUpdate(pkg())
        XCTAssertEqual(status, .pendingVerification)
        let count = await device.count()
        XCTAssertEqual(count, 0)
    }
    func testSameBuildOldCopyMustRemainUnconfirmed() async throws {
        let device = FakeDevice()
        await device.set(app("9"))
        let subject = bridge(device)
        _ = try await subject.installOrUpdate(pkg())
        let result = try await subject.reconcileAfterForeground()
        XCTAssertEqual(result["dev.signed"], .pendingVerification)
        let count = await device.count()
        XCTAssertEqual(count, 0)
    }
    func testObservedNewBuildConfirmsAndClearsPending() async throws {
        let device = FakeDevice()
        await device.set(app("8"))
        let subject = bridge(device)
        _ = try await subject.installOrUpdate(pkg())
        await device.set(app("9"))
        let result = try await subject.reconcileAfterForeground()
        XCTAssertEqual(result["dev.signed"], .confirmed(app("9")))
        let count = await device.count()
        XCTAssertEqual(count, 1)
        let pending = await subject.pendingBundleIdentifiers()
        XCTAssertTrue(pending.isEmpty)
    }
    func testActualDeviceInstallCallbackAllowsSameBuild() async throws {
        let device = FakeDevice()
        await device.set(app("9"))
        let subject = bridge(device)
        _ = try await subject.installOrUpdate(pkg())
        let result = try await subject.installerTransactionCompleted(bundleID: "dev.signed")
        XCTAssertEqual(result, .confirmed(app("9")))
        let count = await device.count()
        XCTAssertEqual(count, 1)
    }
}

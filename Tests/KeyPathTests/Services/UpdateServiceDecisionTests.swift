import Foundation
@testable import KeyPathAppKit
import XCTest

final class UpdateServiceDecisionTests: XCTestCase {
    @MainActor
    func testSessionDownloadsNeverInitializeSparkleOrEnableAutomaticUpdates() {
        let service = UpdateService.testService()
        service.initialize()
        service.setAutomaticChecks(enabled: true)
        service.setAutomaticDownloads(enabled: true)
        XCTAssertTrue(service.usesManualDownloads)
        XCTAssertTrue(service.canCheckForUpdates)
        XCTAssertNil(service.updater)
        XCTAssertFalse(service.automaticallyChecksForUpdates)
        XCTAssertFalse(service.automaticallyDownloadsUpdates)
        XCTAssertFalse(service.allowsAutomaticUpdates)

        var opened: [URL] = []
        var cleanupCalls = 0
        service.configureRuntimeStop { cleanupCalls += 1; return true }
        service.openDownloadPage = { opened.append($0); return true }
        service.checkForUpdates()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://github.com/malpern/KeyPath/releases/latest"])
        XCTAssertEqual(cleanupCalls, 0)
        XCTAssertFalse(service.isUpdateTerminationExpected)
        XCTAssertNil(service.preparationError)
    }

    @MainActor
    func testFailedDownloadPageOpenReportsRecoverableError() {
        let service = UpdateService.testService()
        service.initialize()
        service.openDownloadPage = { _ in false }
        service.checkForUpdates()
        XCTAssertNotNil(service.preparationError)
        service.openDownloadPage = { _ in true }
        service.checkForUpdates()
        XCTAssertNil(service.preparationError)
    }

    @MainActor
    func testUpdateContinuationWaitsForSuccessfulRuntimeCleanup() async {
        var phases: [String] = []
        let result = await UpdateService.continueAfterRuntimeCleanup(stop: {
            phases.append("cleanup")
            await Task.yield()
            phases.append("verified")
            return true
        }, install: { phases.append("install") })
        XCTAssertTrue(result)
        XCTAssertEqual(phases, ["cleanup", "verified", "install"])
    }

    @MainActor
    func testFailedCleanupDoesNotInstallAndSuccessfulRetryInstallsOnce() async {
        var installCount = 0
        let refused = await UpdateService.continueAfterRuntimeCleanup(stop: { false }, install: { installCount += 1 })
        XCTAssertFalse(refused)
        XCTAssertEqual(installCount, 0)
        let retried = await UpdateService.continueAfterRuntimeCleanup(stop: { true }, install: { installCount += 1 })
        XCTAssertTrue(retried)
        XCTAssertEqual(installCount, 1)
    }
    @MainActor
    func testAbortDuringSuspendedCleanupDoesNotInvokeOldHandler() async {
        let service = UpdateService.testService()
        var cleanup: CheckedContinuation<Bool, Never>?
        service.configureRuntimeStop {
            await withCheckedContinuation { cleanup = $0 }
        }
        var installCount = 0
        let preparation = Task { @MainActor in
            await service.postponeInstallation(version: "test", install: { installCount += 1 })
        }
        while cleanup == nil { await Task.yield() }
        service.cancelPreparedUpdate()
        cleanup?.resume(returning: true)
        await preparation.value
        XCTAssertEqual(installCount, 0)
        XCTAssertNil(service.preparationError)
    }

    @MainActor
    func testReplacementAfterAbortReceivesFreshCleanupAndOnlyInstallsNewHandler() async {
        let service = UpdateService.testService()
        var cleanup: CheckedContinuation<Bool, Never>?
        var cleanups = 0
        var preparationActive = false
        service.configureUpdatePreparation { preparationActive = $0 }
        service.configureRuntimeStop {
            cleanups += 1
            if cleanups == 1 { return await withCheckedContinuation { cleanup = $0 } }
            XCTAssertTrue(preparationActive)
            return true
        }
        var installed: [String] = []
        let first = Task { @MainActor in
            await service.postponeInstallation(version: "A", install: { installed.append("A") })
        }
        while cleanup == nil { await Task.yield() }
        service.cancelPreparedUpdate()
        XCTAssertFalse(preparationActive)
        await service.postponeInstallation(version: "B", install: { installed.append("B") })
        XCTAssertTrue(preparationActive)
        cleanup?.resume(returning: false)
        await first.value
        while cleanups < 2 { await Task.yield() }
        while installed.isEmpty { await Task.yield() }
        XCTAssertEqual(installed, ["B"])
        XCTAssertTrue(preparationActive)
        service.cancelPreparedUpdate()
        XCTAssertFalse(preparationActive)
    }

    @MainActor
    func testAbortDuringFailedCleanupDoesNotPublishStaleError() async {
        let service = UpdateService.testService()
        var cleanup: CheckedContinuation<Bool, Never>?
        service.configureRuntimeStop {
            await withCheckedContinuation { cleanup = $0 }
        }
        let preparation = Task { @MainActor in
            await service.postponeInstallation(version: "test", install: { XCTFail("aborted update installed") })
        }
        while cleanup == nil { await Task.yield() }
        service.cancelPreparedUpdate()
        cleanup?.resume(returning: false)
        await preparation.value
        XCTAssertNil(service.preparationError)
    }
}

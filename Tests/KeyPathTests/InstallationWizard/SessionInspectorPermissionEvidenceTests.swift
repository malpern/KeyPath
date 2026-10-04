import Foundation
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class SessionInspectorPermissionEvidenceTests: XCTestCase {
    func testUnknownAndFailedWorkerChecksRequestRuntimeEvidenceInsteadOfConsent() throws {
        for status: PermissionOracle.Status in [.unknown, .error("worker unavailable")] {
            for workerAX in [true, false] {
                let result = inspect(workerAX: workerAX ? status : .granted,
                                     workerIM: workerAX ? .granted : status)
                XCTAssertEqual(result.0, .serviceNotRunning)
                let issue = try XCTUnwrap(result.1.first)
                XCTAssertEqual(issue.identifier, .daemon)
                XCTAssertEqual(issue.autoFixAction, .restartCommServer)
                XCTAssertFalse(issue.description.contains("approval"))
                XCTAssertFalse(issue.description.contains("Full Disk Access"))
            }
        }
    }

    func testConfirmedAppAccessibilityDenialOutranksUnknownWorkerEvidence() {
        let result = inspect(appAX: .denied, workerAX: .unknown, workerIM: .unknown)
        XCTAssertEqual(result.0, .missingPermissions(missing: [.keyPathAccessibility]))
        XCTAssertEqual(result.1.first?.identifier, .permission(.keyPathAccessibility))
        XCTAssertNil(result.1.first?.autoFixAction)
    }

    func testConfirmedWorkerDenialsStillRequestConsent() {
        let ax = inspect(workerAX: .denied)
        XCTAssertEqual(ax.0, .missingPermissions(missing: [.keyPathAccessibility]))
        XCTAssertEqual(ax.1.first?.identifier, .permission(.keyPathAccessibility))
        let im = inspect(workerIM: .denied)
        XCTAssertEqual(im.0, .missingPermissions(missing: [.keyPathInputMonitoring]))
        XCTAssertEqual(im.1.first?.identifier, .permission(.keyPathInputMonitoring))
    }

    func testGrantedChecksWithInactiveTapRequestRuntimeRepair() {
        let result = inspect(tapActive: false)
        XCTAssertEqual(result.0, .serviceNotRunning)
        XCTAssertEqual(result.1.first?.identifier, .daemon)
        XCTAssertEqual(result.1.first?.autoFixAction, .restartCommServer)
    }

    func testGrantedEffectiveInputWithReadyRuntimeIsActiveDespiteRawAppInputDenial() {
        let result = inspect()
        XCTAssertEqual(result.0, .active)
        XCTAssertTrue(result.1.isEmpty)
    }

    private func inspect(
        appAX: PermissionOracle.Status = .granted,
        workerAX: PermissionOracle.Status = .granted,
        workerIM: PermissionOracle.Status = .granted,
        tapActive: Bool = true
    ) -> (WizardSystemState, [WizardIssue]) {
        let now = Date()
        func permissions(_ ax: PermissionOracle.Status, _ im: PermissionOracle.Status) -> PermissionOracle.PermissionSet {
            .init(accessibility: ax, inputMonitoring: im, source: "test", confidence: .high, timestamp: now)
        }
        return SystemInspector.inspect(context: SystemContext(
            permissions: .init(keyPath: permissions(appAX, .denied),
                               kanata: permissions(workerAX, workerIM), timestamp: now, backend: .session),
            services: HealthStatus(backend: .session, kanataProcessRunning: true,
                                   kanataTCPResponding: true, kanataRunning: true,
                                   karabinerDaemonRunning: false, vhidHealthy: false,
                                   kanataInputCaptureReady: tapActive),
            conflicts: .empty,
            components: ComponentStatus(kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true,
                                        karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                                        vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                                        vhidServicesHealthy: false, vhidVersionMismatch: false),
            helper: .empty, system: EngineSystemInfo(macOSVersion: "26.0", driverCompatible: false), timestamp: now
        ))
    }
}

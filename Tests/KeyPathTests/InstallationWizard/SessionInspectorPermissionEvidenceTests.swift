import Foundation
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class SessionInspectorPermissionEvidenceTests: XCTestCase {
    func testUnknownAndFailedRuntimeChecksRequestRuntimeEvidenceInsteadOfConsent() throws {
        for status: PermissionOracle.Status in [.unknown, .error("worker unavailable")] {
            let result = inspect(runtime: status)
            XCTAssertEqual(result.0, .serviceNotRunning)
            let issue = try XCTUnwrap(result.1.first)
            XCTAssertEqual(issue.identifier, .daemon)
            XCTAssertEqual(issue.autoFixAction, .restartCommServer)
            XCTAssertFalse(issue.description.contains("approval"))
            XCTAssertFalse(issue.description.contains("Full Disk Access"))
        }
    }

    func testConfirmedDenialsPublishCanonicalConsentAndReopenGuidance() throws {
        let name = AccessibilityPermissionPresentation.current.name
        let cases: [(PermissionOracle.Status, PermissionOracle.Status, PermissionRequirement, String)] = [
            (.denied, .granted, .keyPathAccessibility,
             "Enable KeyPath in \(name) in System Settings, then quit and reopen KeyPath."),
            (.granted, .denied, .runtimeKeyAccess, "Quit and reopen KeyPath so it can use \(name)."),
        ]
        for (appAX, runtime, requirement, guidance) in cases {
            let result = inspect(appAX: appAX, runtime: runtime)
            let issue = try XCTUnwrap(result.1.first)
            XCTAssertEqual(issue.description, guidance)
            XCTAssertEqual(issue.userAction, guidance)
            XCTAssertNil(issue.autoFixAction)
            XCTAssertEqual(issue.identifier, .permission(requirement))
            XCTAssertEqual(result.0, .missingPermissions(missing: [requirement]))
        }
    }

    func testConfirmedAppAccessibilityDenialOutranksUnknownRuntimeEvidence() {
        let result = inspect(appAX: .denied, runtime: .unknown)
        XCTAssertEqual(result.0, .missingPermissions(missing: [.keyPathAccessibility]))
        XCTAssertEqual(result.1.first?.identifier, .permission(.keyPathAccessibility))
        XCTAssertNil(result.1.first?.autoFixAction)
    }

    func testMissingPayloadOutranksUnavailableRuntimeEvidence() {
        for status: PermissionOracle.Status in [.unknown, .error("worker unavailable")] {
            let result = inspect(runtime: status, payloadPresent: false)
            XCTAssertEqual(result.0, .missingComponents(missing: [.bundledKanataMissing]))
            XCTAssertEqual(result.1.first?.identifier, .component(.bundledKanataMissing))
            XCTAssertNil(result.1.first?.autoFixAction)
        }
        let appDenied = inspect(appAX: .denied, runtime: .unknown, payloadPresent: false)
        XCTAssertEqual(appDenied.0, .missingPermissions(missing: [.keyPathAccessibility]))
    }

    func testUnknownAppAccessibilityRequestsEvidenceWhenPayloadIsPresent() {
        let result = inspect(appAX: .unknown)
        XCTAssertEqual(result.0, .serviceNotRunning)
        XCTAssertEqual(result.1.first?.identifier, .daemon)
        XCTAssertEqual(result.1.first?.autoFixAction, .restartCommServer)
    }

    func testGrantedChecksWithInactiveTapRequestRuntimeRepair() {
        let result = inspect(tapActive: false)
        XCTAssertEqual(result.0, .serviceNotRunning)
        XCTAssertEqual(result.1.first?.identifier, .daemon)
        XCTAssertEqual(result.1.first?.autoFixAction, .restartCommServer)
    }

    func testGrantedPermissionsWithReadyRuntimeAreActive() {
        let result = inspect()
        XCTAssertEqual(result.0, .active)
        XCTAssertTrue(result.1.isEmpty)
    }

    private func inspect(
        appAX: PermissionOracle.Status = .granted,
        runtime: PermissionOracle.Status = .granted,
        tapActive: Bool = true,
        payloadPresent: Bool = true
    ) -> (WizardSystemState, [WizardIssue]) {
        let now = Date()
        return SystemInspector.inspect(context: SystemContext(
            permissions: PermissionOracle.Snapshot(
                accessibility: appAX,
                runtimeKeyAccess: .init(status: runtime, source: "test", confidence: .high, timestamp: now),
                timestamp: now
            ),
            services: HealthStatus(backend: .session, kanataProcessRunning: true,
                                   kanataTCPResponding: true, kanataRunning: true,
                                   karabinerDaemonRunning: false, vhidHealthy: false,
                                   kanataInputCaptureReady: tapActive),
            conflicts: .empty,
            components: ComponentStatus(kanataBinaryInstalled: payloadPresent, requiredRuntimePayloadPresent: payloadPresent,
                                        karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                                        vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                                        vhidServicesHealthy: false, vhidVersionMismatch: false),
            system: EngineSystemInfo(macOSVersion: "26.0", driverCompatible: false), timestamp: now
        ))
    }
}

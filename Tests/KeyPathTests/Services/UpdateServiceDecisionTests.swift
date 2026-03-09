import Foundation
@testable import KeyPathAppKit
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class UpdateServiceDecisionTests: XCTestCase {
    func testPreUpdateDecisionUsesSoftRepairWhenHelperPresent() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: false
        )

        let decision = UpdateService.preUpdateDecision(for: context)
        XCTAssertEqual(decision, .softRepair(reason: "reason_code=services_or_helper_present"))
    }

    func testPreUpdateDecisionContinuesSilentlyWhenNothingRunning() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: false,
            componentsReady: false,
            servicesReady: false
        )

        let decision = UpdateService.preUpdateDecision(for: context)
        XCTAssertEqual(decision, .silentContinue(reason: "reason_code=nothing_running"))
    }

    func testPostUpdateDecisionHardRepairWhenKeyPathPermissionsBlocking() {
        let context = makeContext(
            keyPathStatus: .denied,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .hardRepair(reason: "reason_code=keypath_permissions_blocking"))
    }

    func testPostUpdateDecisionHardRepairWhenKanataPermissionsBlocking() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .denied,
            helperReady: true,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .hardRepair(reason: "reason_code=kanata_permissions_blocking"))
    }

    func testPostUpdateDecisionSoftRepairWhenHelperNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: false,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .softRepair(reason: "reason_code=helper_not_ready"))
    }

    func testPostUpdateDecisionSoftRepairWhenComponentsNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: false,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .softRepair(reason: "reason_code=components_not_ready"))
    }

    func testPostUpdateDecisionSoftRepairWhenServicesNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: false
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .softRepair(reason: "reason_code=components_not_ready"))
    }

    func testPostUpdateDecisionContinuesSilentlyWhenHealthy() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .silentContinue(reason: "reason_code=healthy"))
    }

    private func makeContext(
        keyPathStatus: PermissionOracle.Status,
        kanataStatus: PermissionOracle.Status,
        helperReady: Bool,
        componentsReady: Bool,
        servicesReady: Bool
    ) -> SystemContext {
        let now = Date()
        let keyPathPerms = PermissionOracle.PermissionSet(
            accessibility: keyPathStatus,
            inputMonitoring: keyPathStatus,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let kanataPerms = PermissionOracle.PermissionSet(
            accessibility: kanataStatus,
            inputMonitoring: kanataStatus,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let permissions = PermissionOracle.Snapshot(
            keyPath: keyPathPerms,
            kanata: kanataPerms,
            timestamp: now
        )

        let components: ComponentStatus = if componentsReady {
            ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: servicesReady,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: servicesReady,
                vhidServicesHealthy: servicesReady,
                vhidVersionMismatch: false,
                kanataBinaryVersionMismatch: false
            )
        } else {
            .empty
        }

        let health = HealthStatus(
            kanataRunning: servicesReady,
            karabinerDaemonRunning: servicesReady,
            vhidHealthy: servicesReady
        )

        return SystemContext(
            permissions: permissions,
            services: health,
            conflicts: .empty,
            components: components,
            helper: HelperStatus(isInstalled: helperReady, version: "1.0", isWorking: helperReady),
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: now
        )
    }
}

import Foundation
@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class UpdateServiceDecisionTests: XCTestCase {
    func testPreUpdateDecisionAllowsAutomaticRepairDuringUpdateInstallWhenHelperPresent() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: false
        )

        let decision = UpdateService.preUpdateDecision(for: context)
        XCTAssertEqual(decision, .automaticRepairAllowed(reason: "reason_code=services_or_helper_present"))
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

    func testPostUpdateDecisionRequiresManualAttentionWhenKeyPathPermissionsBlocking() {
        let context = makeContext(
            keyPathStatus: .denied,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .manualAttentionRequired(reason: "reason_code=keypath_permissions_blocking"))
    }

    /// #931: KeyPath's own Input Monitoring is soft (overlay/record only). With
    /// KeyPath Accessibility granted, a denied KeyPath IM must NOT force a hard
    /// post-update repair — only kanata's permissions and KeyPath AX are hard.
    func testPostUpdateDecisionIgnoresKeyPathInputMonitoringAlone() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: true,
            keyPathInputMonitoring: .denied
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .silentContinue(reason: "reason_code=healthy"))
    }

    func testPostUpdateDecisionRequiresManualAttentionWhenKanataPermissionsBlocking() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .denied,
            helperReady: true,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .manualAttentionRequired(reason: "reason_code=kanata_permissions_blocking"))
    }

    func testPostUpdateDecisionRequiresUserRepairWhenHelperNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: false,
            componentsReady: true,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .userRepairRequired(reason: "reason_code=helper_not_ready"))
    }

    func testPostUpdateDecisionRequiresUserRepairWhenComponentsNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: false,
            servicesReady: true
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .userRepairRequired(reason: "reason_code=components_not_ready"))
    }

    func testPostUpdateDecisionRequiresUserRepairWhenServicesNotReady() {
        let context = makeContext(
            keyPathStatus: .granted,
            kanataStatus: .granted,
            helperReady: true,
            componentsReady: true,
            servicesReady: false
        )

        let decision = UpdateService.postUpdateDecision(for: context)
        XCTAssertEqual(decision, .userRepairRequired(reason: "reason_code=components_not_ready"))
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
        servicesReady: Bool,
        keyPathInputMonitoring: PermissionOracle.Status? = nil
    ) -> SystemContext {
        let now = Date()
        let keyPathPerms = PermissionOracle.PermissionSet(
            accessibility: keyPathStatus,
            inputMonitoring: keyPathInputMonitoring ?? keyPathStatus,
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
                vhidVersionMismatch: false
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

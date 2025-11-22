import Foundation
import XCTest

@testable import KeyPathAppKit
@testable import KeyPathPermissions
@testable import KeyPathWizardCore

@MainActor
final class WizardStateMachineDeterminismTests: XCTestCase {
    // Helper builders for concise snapshots
    private func makePermissions(
        keyPathAX: PermissionOracle.Status,
        keyPathIM: PermissionOracle.Status,
        kanataAX: PermissionOracle.Status,
        kanataIM: PermissionOracle.Status
    ) -> PermissionOracle.Snapshot {
        let now = Date()
        let kp = PermissionOracle.PermissionSet(
            accessibility: keyPathAX,
            inputMonitoring: keyPathIM,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let ka = PermissionOracle.PermissionSet(
            accessibility: kanataAX,
            inputMonitoring: kanataIM,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        return PermissionOracle.Snapshot(keyPath: kp, kanata: ka, timestamp: now)
    }

    private func makeSnapshot(
        helperInstalled: Bool,
        helperWorking: Bool,
        conflicts: [SystemConflict],
        keyPathAX: PermissionOracle.Status,
        keyPathIM: PermissionOracle.Status,
        kanataAX: PermissionOracle.Status,
        kanataIM: PermissionOracle.Status,
        components: ComponentStatus
    ) -> SystemSnapshot {
        SystemSnapshot(
            permissions: makePermissions(
                keyPathAX: keyPathAX,
                keyPathIM: keyPathIM,
                kanataAX: kanataAX,
                kanataIM: kanataIM
            ),
            components: components,
            conflicts: ConflictStatus(conflicts: conflicts, canAutoResolve: false),
            health: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: false),
            helper: HelperStatus(isInstalled: helperInstalled, version: nil, isWorking: helperWorking),
            timestamp: Date()
        )
    }

    private var allComponentsMissing: ComponentStatus {
        ComponentStatus(
            kanataBinaryInstalled: false,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: false,
            vhidDeviceHealthy: false,
            launchDaemonServicesHealthy: false,
            vhidVersionMismatch: false
        )
    }

    private var allComponentsReady: ComponentStatus {
        ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            launchDaemonServicesHealthy: true,
            vhidVersionMismatch: false
        )
    }

    func testNextPageDeterministicFlow() {
        let machine = WizardStateMachine()

        // Start on summary
        machine.currentPage = .summary

        // 1) Helper missing -> helper page
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: false,
            helperWorking: false,
            conflicts: [],
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .granted,
            kanataIM: .granted,
            components: allComponentsReady
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .helper)

        // 2) Helper ready, conflicts present -> conflicts page
        machine.currentPage = .summary
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: true,
            helperWorking: true,
            conflicts: [.kanataProcessRunning(pid: 1234, command: "kanata")],
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .granted,
            kanataIM: .granted,
            components: allComponentsReady
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .conflicts)

        // 3) No conflicts, KeyPath IM missing -> inputMonitoring page
        machine.currentPage = .summary
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: true,
            helperWorking: true,
            conflicts: [],
            keyPathAX: .granted,
            keyPathIM: .denied,
            kanataAX: .granted,
            kanataIM: .granted,
            components: allComponentsReady
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .inputMonitoring)

        // 4) KeyPath ok, Kanata missing -> accessibility page
        machine.currentPage = .summary
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: true,
            helperWorking: true,
            conflicts: [],
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .denied,
            components: allComponentsReady
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .accessibility)

        // 5) Permissions ok, components missing -> karabinerComponents page
        machine.currentPage = .summary
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: true,
            helperWorking: true,
            conflicts: [],
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .granted,
            kanataIM: .granted,
            components: allComponentsMissing
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .karabinerComponents)

        // 6) All good -> service page
        machine.currentPage = .summary
        machine.systemSnapshot = makeSnapshot(
            helperInstalled: true,
            helperWorking: true,
            conflicts: [],
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .granted,
            kanataIM: .granted,
            components: allComponentsReady
        )
        machine.nextPage()
        XCTAssertEqual(machine.currentPage, .service)
    }
}

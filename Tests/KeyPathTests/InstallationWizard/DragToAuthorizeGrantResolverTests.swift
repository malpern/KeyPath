@testable import KeyPathInstallationWizard
import KeyPathPermissions
@preconcurrency import XCTest

/// Covers the pure target×subject → grant mapping used by the drag-to-authorize
/// overlay (#933). The overlay must poll the correct app's correct permission:
/// `.keyPath` reads `snapshot.keyPath`, `.kanata` reads `snapshot.kanata`, and
/// Full Disk Access comes from the separate FDA signal, not the snapshot.
final class DragToAuthorizeGrantResolverTests: XCTestCase {
    private typealias Target = DragToAuthorizeController.PermissionTarget
    private typealias Subject = DragToAuthorizeController.PermissionSubject

    private func permissionSet(ax: PermissionOracle.Status, im: PermissionOracle.Status)
        -> PermissionOracle.PermissionSet
    {
        PermissionOracle.PermissionSet(
            accessibility: ax, inputMonitoring: im, source: "test", confidence: .high, timestamp: Date()
        )
    }

    private func snapshot(
        keyPathAX: PermissionOracle.Status = .denied,
        keyPathIM: PermissionOracle.Status = .denied,
        kanataAX: PermissionOracle.Status = .denied,
        kanataIM: PermissionOracle.Status = .denied
    ) -> PermissionOracle.Snapshot {
        PermissionOracle.Snapshot(
            keyPath: permissionSet(ax: keyPathAX, im: keyPathIM),
            kanata: permissionSet(ax: kanataAX, im: kanataIM),
            timestamp: Date()
        )
    }

    private func resolve(
        _ target: Target, _ subject: Subject,
        _ snapshot: PermissionOracle.Snapshot, fda: Bool = false
    ) -> Bool {
        DragToAuthorizeController.grantResolved(
            target: target, subject: subject, snapshot: snapshot, fullDiskAccessGranted: fda
        )
    }

    func testAccessibilityReadsTheChosenSubjectsRow() {
        let snap = snapshot(keyPathAX: .granted, kanataAX: .denied)
        XCTAssertTrue(resolve(.accessibility, .keyPath, snap))
        XCTAssertFalse(resolve(.accessibility, .kanata, snap))
    }

    func testInputMonitoringReadsTheChosenSubjectsRow() {
        let snap = snapshot(keyPathIM: .denied, kanataIM: .granted)
        XCTAssertFalse(resolve(.inputMonitoring, .keyPath, snap))
        XCTAssertTrue(resolve(.inputMonitoring, .kanata, snap))
    }

    func testTargetSelectsPermissionWithinTheSameSubject() {
        // KeyPath AX granted but IM denied — target must not cross-read.
        let snap = snapshot(keyPathAX: .granted, keyPathIM: .denied)
        XCTAssertTrue(resolve(.accessibility, .keyPath, snap))
        XCTAssertFalse(resolve(.inputMonitoring, .keyPath, snap))
    }

    func testNonGrantedStatusesAreNotTreatedAsGranted() {
        for status in [PermissionOracle.Status.denied, .unknown, .error("x")] {
            let snap = snapshot(keyPathAX: status)
            XCTAssertFalse(resolve(.accessibility, .keyPath, snap), "\(status) must not count as granted")
        }
    }

    func testFullDiskAccessUsesTheSeparateSignalNotTheSnapshot() {
        // Snapshot rows are all denied; FDA is driven solely by the passed-in flag.
        let snap = snapshot()
        XCTAssertTrue(resolve(.fullDiskAccess, .keyPath, snap, fda: true))
        XCTAssertFalse(resolve(.fullDiskAccess, .keyPath, snap, fda: false))
    }
}

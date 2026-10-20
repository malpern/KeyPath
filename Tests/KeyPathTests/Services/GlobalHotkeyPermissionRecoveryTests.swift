import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class GlobalHotkeyPermissionRecoveryTests: XCTestCase {
    func testGrantAfterInitialDeniedStartInstallsMonitorsOnce() {
        let center = NotificationCenter()
        var granted = false
        var globalCount = 0
        var localCount = 0
        let service = GlobalHotkeyService(
            notificationCenter: center, permissionsReady: { granted },
            addGlobalMonitor: { _ in globalCount += 1; return NSObject() },
            addLocalMonitor: { _ in localCount += 1; return NSObject() },
            removeMonitor: { _ in }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        service.startMonitoring()
        XCTAssertEqual(globalCount, 0)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 0)
        granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 1)
        XCTAssertEqual(localCount, 1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 1)
        XCTAssertEqual(localCount, 1)
    }

    func testFailedGlobalMonitorRetryDoesNotLeakLocalMonitor() {
        let center = NotificationCenter()
        var globalCount = 0
        var localCount = 0
        var removedCount = 0
        let service = GlobalHotkeyService(
            notificationCenter: center, permissionsReady: { true },
            addGlobalMonitor: { _ in
                globalCount += 1
                return globalCount == 1 ? nil : NSObject()
            },
            addLocalMonitor: { _ in localCount += 1; return NSObject() },
            removeMonitor: { _ in removedCount += 1 }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        service.startMonitoring()
        XCTAssertEqual(localCount, 1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(globalCount, 2)
        XCTAssertEqual(localCount, 1, "Retry must retain the already-installed local monitor")
        service.stopMonitoring()
        XCTAssertEqual(removedCount, 2, "Every installed monitor must remain owned until removal")
    }

    func testStopCancelsPendingGrantRecovery() {
        let center = NotificationCenter()
        var granted = false
        var installed = 0
        let service = GlobalHotkeyService(
            notificationCenter: center, permissionsReady: { granted },
            addGlobalMonitor: { _ in installed += 1; return NSObject() },
            addLocalMonitor: { _ in NSObject() }, removeMonitor: { _ in }
        )
        let key = "KeyPath.GlobalHotkey.Enabled"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            service.stopMonitoring()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        service.startMonitoring()
        service.stopMonitoring()
        granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(installed, 0)
    }
}

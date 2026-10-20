import AppKit
@testable import KeyPathAppKit
import SwiftUI
import XCTest

/// Rendered regression coverage for the driverless keyboard information panel.
/// The mixed fixture proves virtual devices stay hidden and physical rows have
/// no exclusion toggles or restart action.
final class DeviceSelectionSnapshotTests: ScreenshotTestCase {
    func testConnectedKeyboardInformation() {
        _ = NSApplication.shared
        let devices = [
            ConnectedDevice(hash: "internal", vendorID: 0x05AC, productID: 1,
                            productKey: "Apple Internal Keyboard / Trackpad", isVirtualHID: false),
            ConnectedDevice(hash: "external", vendorID: 0x1234, productID: 2,
                            productKey: "External Keyboard", isVirtualHID: false),
            ConnectedDevice(hash: "virtual", vendorID: 0x1234, productID: 3,
                            productKey: "Hidden Virtual Keyboard", isVirtualHID: true)
        ]
        assertScreenshot(
            of: DeviceSelectionView(devices: devices)
                .environment(MockFactories.kanataViewModel())
                .padding(16)
                .frame(width: 360, height: 400)
                .background(Color.white),
            size: CGSize(width: 360, height: 400),
            named: "driverless-connected-keyboards"
        )
    }

    func testNoConnectedKeyboards() {
        _ = NSApplication.shared
        assertScreenshot(
            of: DeviceSelectionView(devices: [])
                .environment(MockFactories.kanataViewModel())
                .padding(16)
                .frame(width: 360, height: 400)
                .background(Color.white),
            size: CGSize(width: 360, height: 400),
            named: "driverless-no-keyboards"
        )
    }
}

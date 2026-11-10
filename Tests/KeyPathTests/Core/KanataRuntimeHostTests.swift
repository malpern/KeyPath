@testable import KeyPathCore
import XCTest

final class KanataRuntimeHostTests: XCTestCase {
    func testCurrentUsesBundleRelativePaths() {
        let host = KanataRuntimeHost.current(bundlePath: "/Applications/KeyPath.app")
        XCTAssertEqual(host.bridgeLibraryPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        XCTAssertEqual(host.bundledCorePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        XCTAssertEqual(host.kanataEngineBundlePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }

    func testCurrentNormalizesLibraryDirectoryToAppBundleRoot() {
        let host = KanataRuntimeHost.current(
            bundlePath: "/Applications/KeyPath.app/Contents/Library/KeyPath"
        )
        XCTAssertEqual(host.bridgeLibraryPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        XCTAssertEqual(host.bundledCorePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        XCTAssertEqual(host.kanataEngineBundlePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }

    func testAppBundlePathFindsContainingAppFromBundledCLI() {
        XCTAssertEqual(
            KanataRuntimeHost.appBundlePath(
                containing: "/Applications/KeyPath.app/Contents/MacOS/keypath-cli"
            ),
            "/Applications/KeyPath.app"
        )
    }

    func testPreferredCoreBinaryAlwaysReturnsBundledPath() {
        let host = KanataRuntimeHost(
            bridgeLibraryPath: "/tmp/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
            kanataEngineBundlePath: "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app"
        )

        XCTAssertEqual(host.preferredCoreBinaryPath(), host.bundledCorePath)
    }

    func testKanataEngineBundleIDIsCorrect() {
        XCTAssertEqual(KeyPathConstants.Bundle.kanataEngineBundleID, "com.keypath.kanata-engine")
    }
}

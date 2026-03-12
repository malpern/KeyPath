@testable import KeyPathCore
import XCTest

final class KanataRuntimeHostTests: XCTestCase {
    func testCurrentUsesBundleRelativePaths() {
        let host = KanataRuntimeHost.current(bundlePath: "/Applications/KeyPath.app")

        XCTAssertEqual(host.launcherPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher")
        XCTAssertEqual(host.bridgeLibraryPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        XCTAssertEqual(host.bundledCorePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata")
    }

    func testCurrentNormalizesLauncherExecutableDirectoryToAppBundleRoot() {
        let host = KanataRuntimeHost.current(
            bundlePath: "/Applications/KeyPath.app/Contents/Library/KeyPath"
        )

        XCTAssertEqual(host.launcherPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher")
        XCTAssertEqual(host.bridgeLibraryPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        XCTAssertEqual(host.bundledCorePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata")
    }

    func testPreferredCoreBinaryAlwaysReturnsBundledPath() {
        let host = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/tmp/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata"
        )

        XCTAssertEqual(host.preferredCoreBinaryPath(), host.bundledCorePath)
    }

    func testDeprecatedSystemCorePathReturnsBundledCorePath() {
        let host = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/tmp/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata"
        )

        // systemCorePath is a deprecated alias — must always equal bundledCorePath
        XCTAssertEqual(host.systemCorePath, host.bundledCorePath)
    }

    func testLaunchRequestBuildsCommandLineAndAddsTraceWhenNeeded() {
        let request = KanataRuntimeLaunchRequest(
            configPath: "/Users/test/.config/keypath/keypath.kbd",
            inheritedArguments: ["--port", "37001", "--log-layer-changes"],
            addTraceLogging: true
        )

        XCTAssertEqual(
            request.commandLine(binaryPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata"),
            [
                "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata",
                "--cfg", "/Users/test/.config/keypath/keypath.kbd",
                "--port", "37001",
                "--log-layer-changes",
                "--trace"
            ]
        )
    }

    func testLaunchRequestDoesNotDuplicateTraceWhenDebugAlreadyPresent() {
        let request = KanataRuntimeLaunchRequest(
            configPath: "/Users/test/.config/keypath/keypath.kbd",
            inheritedArguments: ["--debug"],
            addTraceLogging: true
        )

        XCTAssertEqual(
            request.commandLine(binaryPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata"),
            [
                "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata",
                "--cfg", "/Users/test/.config/keypath/keypath.kbd",
                "--debug"
            ]
        )
    }
}

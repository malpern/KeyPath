import Foundation
import KeyPathCore
@preconcurrency import XCTest

/// Pins the driverless app's remaining permission-bearing identities and package boundary.
final class IdentityStabilityContractTests: XCTestCase {
    private let root = repositoryRoot()

    func testKanataEngineIdentityAndRuntimePathsRemainStable() throws {
        XCTAssertEqual(KeyPathConstants.Bundle.kanataEngineBundleID, "com.keypath.kanata-engine")
        let host = KanataRuntimeHost.current(bundlePath: "/Applications/KeyPath.app")
        XCTAssertEqual(host.kanataEngineBundlePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
        XCTAssertEqual(host.bundledCorePath, "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        XCTAssertEqual(host.bridgeLibraryPath, "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")

        let engineInfo = try plist(at: root.appendingPathComponent("Sources/KeyPathApp/Resources/KanataEngine-Info.plist"))
        XCTAssertEqual(engineInfo["CFBundleIdentifier"] as? String, "com.keypath.kanata-engine")
        XCTAssertEqual(engineInfo["CFBundleExecutable"] as? String, "kanata")
    }

    func testDriverlessIdentityVerifierRejectsLegacyPayloadAndChecksRemainingComponents() throws {
        let verifier = try contents("Scripts/verify-identity-contract.sh")
        for required in [
            "Karabiner-DriverKit-VirtualHIDDevice-*.pkg",
            "KeyPathHelper",
            "kanata-launcher",
            "LaunchDaemons",
            "SMPrivilegedExecutables",
            "com.keypath.KeyPath.CLI",
            "com.keypath.kanata-host-bridge",
            "com.keypath.kanata-simulator",
            "Kanata Engine.app",
            "DEVELOPER_ID_AUTHORITY",
            "uses hardened runtime",
            "designated requirement is stable"
        ] {
            XCTAssertTrue(verifier.contains(required), "Identity verifier missing driverless contract: \(required)")
        }
    }

    func testReleaseBuildIsProductScopedAndKeepsHardenedSigning() throws {
        let build = try contents("Scripts/build-and-sign.sh")
        let signingContract = try contents("Scripts/verify-release-signing-contract.sh")
        let package = try contents("Package.swift")
        XCTAssertTrue(build.contains("for product in KeyPath keypath-cli KeyPathInsights"))
        XCTAssertTrue(package.contains("\"com.keypath.kanata.plist\""))
        XCTAssertFalse(build.contains("./Scripts/build-helper.sh"))
        XCTAssertFalse(build.contains("KeyPathHelper"))
        XCTAssertFalse(build.contains("kanata-launcher"))
        XCTAssertFalse(build.contains("LaunchDaemons"))
        XCTAssertTrue(build.contains("--entitlements \"$ENTITLEMENTS_FILE\""))
        XCTAssertTrue(build.contains("--options=runtime"))
        XCTAssertTrue(signingContract.contains("main app Info.plist omits SMPrivilegedExecutables"))
        XCTAssertTrue(signingContract.contains("stable hardened-runtime identity"))
    }

    func testMainAppNoLongerDeclaresPrivilegedHelper() throws {
        let mainInfo = try plist(at: root.appendingPathComponent("Sources/KeyPathApp/Info.plist"))
        XCTAssertNil(mainInfo["SMPrivilegedExecutables"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/KeyPathApp/Resources/Karabiner-DriverKit-VirtualHIDDevice-8.0.0.pkg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/KeyPathApp/Resources/uninstall.sh").path))
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private func plist(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    guard let dictionary = value as? [String: Any] else {
        throw NSError(domain: "IdentityStabilityContractTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Expected dictionary plist at \(url.path)"
        ])
    }
    return dictionary
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

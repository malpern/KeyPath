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
            "--payload-only",
            "verify_payload_only_contract",
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

    func testPayloadOnlyVerifierRejectsNestedForbiddenPackageWithoutCodeSigning() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("driverless-payload-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let app = temporaryRoot.appendingPathComponent("KeyPath.app", isDirectory: true)
        let contentsURL = app.appendingPathComponent("Contents", isDirectory: true)
        let resourceBundle = contentsURL
            .appendingPathComponent("Resources/KeyPath_KeyPathApp.bundle/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourceBundle, withIntermediateDirectories: true)
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.keypath.KeyPath</string></dict></plist>
        """
        try info.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let forbiddenPackage = resourceBundle.appendingPathComponent("Karabiner-DriverKit-VirtualHIDDevice-99.0.pkg")
        XCTAssertTrue(FileManager.default.createFile(atPath: forbiddenPackage.path, contents: Data()))

        let verifier = root.appendingPathComponent("Scripts/verify-identity-contract.sh")
        let process = Process()
        process.executableURL = verifier
        process.arguments = ["--payload-only", app.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let result = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 1, result)
        XCTAssertTrue(result.contains("forbidden packaged driver/helper asset exists"), result)
        XCTAssertTrue(result.contains(forbiddenPackage.lastPathComponent), result)
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

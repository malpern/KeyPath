import Foundation
import KeyPathCore
@preconcurrency import XCTest

/// Pins the Workstream 4 identity contract for the components whose identity
/// affects TCC, SMAppService, or launchd LWCR caching.
final class IdentityStabilityContractTests: XCTestCase {
    private static let kanataEngineID = "com.keypath.kanata-engine"
    private static let helperID = "com.keypath.helper"
    private static let kanataDaemonID = "com.keypath.kanata"
    private static let canonicalAppPath = "/Applications/KeyPath.app"
    private static let kanataDesignatedRequirement =
        #"identifier "com.keypath.kanata-engine" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99"#
    private static let helperDesignatedRequirement =
        #"identifier "com.keypath.helper" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99"#
    private static let launcherDesignatedRequirement =
        #"identifier "kanata-launcher" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X2RKZ5TG99"#

    func testPinnedSourceIdentityContract() throws {
        XCTAssertEqual(KeyPathConstants.Bundle.kanataEngineBundleID, Self.kanataEngineID)
        XCTAssertEqual(KeyPathConstants.Bundle.helperID, Self.helperID)
        XCTAssertEqual(KeyPathConstants.Bundle.daemonID, Self.kanataDaemonID)

        let runtimeHost = KanataRuntimeHost.current(bundlePath: Self.canonicalAppPath)
        XCTAssertEqual(
            runtimeHost.kanataEngineBundlePath,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app"
        )
        XCTAssertEqual(
            runtimeHost.bundledCorePath,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata"
        )
        XCTAssertEqual(
            runtimeHost.launcherPath,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher"
        )

        let root = repositoryRoot()
        let kanataInfo = try plist(at: root.appendingPathComponent("Sources/KeyPathApp/Resources/KanataEngine-Info.plist"))
        XCTAssertEqual(kanataInfo["CFBundleIdentifier"] as? String, Self.kanataEngineID)
        XCTAssertEqual(kanataInfo["CFBundleExecutable"] as? String, "kanata")

        let helperInfo = try plist(at: root.appendingPathComponent("Sources/KeyPathHelper/Info.plist"))
        XCTAssertEqual(helperInfo["CFBundleIdentifier"] as? String, Self.helperID)

        let helperPlist = try plist(at: root.appendingPathComponent("Sources/KeyPathHelper/com.keypath.helper.plist"))
        XCTAssertEqual(helperPlist["Label"] as? String, Self.helperID)
        XCTAssertEqual(helperPlist["BundleProgram"] as? String, "Contents/Library/HelperTools/KeyPathHelper")
        XCTAssertEqual((helperPlist["MachServices"] as? [String: Bool])?[Self.helperID], true)

        let kanataPlist = try plist(at: root.appendingPathComponent("Sources/KeyPathApp/com.keypath.kanata.plist"))
        XCTAssertEqual(kanataPlist["Label"] as? String, Self.kanataDaemonID)
        XCTAssertEqual(kanataPlist["BundleProgram"] as? String, "Contents/Library/KeyPath/kanata-launcher")
        XCTAssertEqual((kanataPlist["ProgramArguments"] as? [String])?.first, "Contents/Library/KeyPath/kanata-launcher")
        XCTAssertEqual((kanataPlist["AssociatedBundleIdentifiers"] as? [String])?.first, "com.keypath.KeyPath")
    }

    func testReleaseGateInvokesIdentityContractScript() throws {
        let root = repositoryRoot()
        let verifier = root.appendingPathComponent("Scripts/verify-identity-contract.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: verifier.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: verifier.path))

        let verifierContents = try String(contentsOf: verifier, encoding: .utf8)
        XCTAssertTrue(verifierContents.contains(Self.kanataDesignatedRequirement))
        XCTAssertTrue(verifierContents.contains(Self.helperDesignatedRequirement))
        XCTAssertTrue(verifierContents.contains(Self.launcherDesignatedRequirement))

        let releaseDoctor = try String(
            contentsOf: root.appendingPathComponent("Scripts/release-doctor.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(releaseDoctor.contains("verify-identity-contract.sh\" --source"))

        let buildAndSign = try String(
            contentsOf: root.appendingPathComponent("Scripts/build-and-sign.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(buildAndSign.contains("\"$SCRIPT_DIR/verify-identity-contract.sh\" --app \"$APP_BUNDLE\""))
    }

    func testIdentityADRDocumentsPinnedContract() throws {
        let root = repositoryRoot()
        let adr = try String(
            contentsOf: root.appendingPathComponent("docs/adr/adr-041-installer-identity-stability-contract.md"),
            encoding: .utf8
        )

        for requiredText in [
            Self.kanataEngineID,
            Self.helperID,
            Self.kanataDaemonID,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
            "/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper",
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher",
            Self.kanataDesignatedRequirement,
            Self.helperDesignatedRequirement,
            Self.launcherDesignatedRequirement,
            "installPrivilegedHelper",
            "reinstallPrivilegedHelper",
            "com.keypath.KeyPath.Helper",
            "HelperMaintenance",
            "codesign -d -r- --verbose=4",
            "reformat the requirement string",
            "Scripts/verify-identity-contract.sh"
        ] {
            XCTAssertTrue(adr.contains(requiredText), "ADR missing identity-contract text: \(requiredText)")
        }
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
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

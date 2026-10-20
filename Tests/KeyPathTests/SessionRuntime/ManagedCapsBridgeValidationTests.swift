import Foundation
import KeyPathCore
import XCTest

/// Exercise the additive C ABI through the Swift loader, never an installed app
/// fallback, capture runtime, or HID property mutation.
final class ManagedCapsBridgeValidationTests: XCTestCase {
    private func validate(_ text: String, managed: Bool, reserving: UInt32 = 109,
                          host: KanataRuntimeHost = SessionBridgeTestFixture.runtimeHost) throws -> KanataHostBridgeValidationResult
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("caps.kbd")
        try text.write(to: path, atomically: true, encoding: .utf8)
        return KanataHostBridge.validateSessionConfig(
            runtimeHost: host, configPath: path.path, supportedUsages: [4, 5, 41, 109, 110, 224], managedCaps: managed,
            reservedUsage: reserving
        )
    }

    func testManagedInputAdmissionDoesNotChangeLegacyCapsRejection() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let text = "(defsrc caps a)(deflayer base (tap-hold 200 200 esc lctl) a)"
        guard case .invalid = try validate(text, managed: false) else { return XCTFail("Legacy Caps gate must stay closed") }
        guard case .valid = try validate(text, managed: true) else { return XCTFail("Managed Caps tap/hold must validate") }
        guard case .valid = try validate("(defsrc a)(deflayer base b)", managed: false) else {
            return XCTFail("Legacy ordinary remapping must remain eligible")
        }
    }

    func testManagedModeRejectsReservedOutputsAndImplicitSourceActions() throws {
        try SessionBridgeTestFixture.requireAvailable()
        for action in ["f18", "_", "use-defsrc", "rpt-any", "(macro f18)"] {
            guard case .invalid = try validate("(defsrc caps a)(deflayer base \(action) a)", managed: true) else {
                XCTFail("Unsafe managed action admitted: \(action)")
                continue
            }
        }
        guard case .invalid = try validate("(defsrc caps f18)(deflayer base esc a)", managed: true) else {
            return XCTFail("Native F18 input must stay reserved")
        }
    }

    func testChosenIntermediateIsReservedThroughTheCABI() throws {
        try SessionBridgeTestFixture.requireAvailable()
        guard case .valid = try validate("(defsrc caps f18)(deflayer base esc f18)", managed: true, reserving: 110) else {
            return XCTFail("F18 is ordinary when F19 is the intermediate")
        }
        for text in ["(defsrc caps f19)(deflayer base esc a)", "(defsrc caps a)(deflayer base esc f19)"] {
            guard case .invalid = try validate(text, managed: true, reserving: 110) else { return XCTFail("F19 must be reserved: \(text)") }
        }
        guard case .invalid = try validate("(defsrc caps)(deflayer base esc)", managed: true, reserving: 112) else {
            return XCTFail("F21 cannot be an intermediate")
        }
    }

    func testManagedCapsOutputsAreAdmitted() throws {
        try SessionBridgeTestFixture.requireAvailable()
        for action in ["caps", "(tap-hold 200 200 esc caps)"] {
            let text = "(defsrc caps a)(deflayer base \(action) a)"
            guard case .valid = try validate(text, managed: true) else { return XCTFail("Managed Caps output refused") }
        }
    }

    func testOlderBridgeCannotSilentlyFallBackForManagedCaps() throws {
        guard let path = ProcessInfo.processInfo.environment["KEYPATH_SESSION_LEGACY_TEST_BRIDGE_PATH"] else {
            throw XCTSkip("Supply an explicit older bridge to verify missing-symbol refusal")
        }
        let host = KanataRuntimeHost(launcherPath: "/unused", bridgeLibraryPath: path,
                                     bundledCorePath: "/unused", kanataEngineBundlePath: "/unused")
        guard case let .unavailable(reason) = try validate("(defsrc caps)(deflayer base esc)", managed: true, host: host) else {
            return XCTFail("Older bridge must refuse managed admission")
        }
        XCTAssertEqual(reason, "managed Caps profile validator missing")
        guard case .valid = try validate("(defsrc a)(deflayer base b)", managed: false, host: host) else {
            return XCTFail("Older bridge still supports legacy admission")
        }
    }

    func testManagedAdmissionRefusesMalformedConfiguration() throws {
        try SessionBridgeTestFixture.requireAvailable()
        guard case .invalid = try validate("(defsrc caps)(deflayer base", managed: true) else {
            return XCTFail("Malformed profile must be rejected")
        }
    }
}

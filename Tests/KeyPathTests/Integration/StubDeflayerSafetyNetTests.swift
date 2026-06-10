@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests the generator's orphan-layer safety net.
///
/// When a rule references a layer that no other enabled rule provides
/// (most visibly: Home Row Layer Toggles in toggle mode referencing the
/// Function/Symbol/Numpad layers when those families are disabled), the
/// generator emits a stub `(deflayer ...)` block so kanata accepts the
/// config. Keys mapped into the orphan layer then degrade to transparent
/// (`_`) instead of the whole config failing to load.
///
/// Background: pre-fix, the scanner caught `layer-while-held` and
/// `layer-switch` references but missed `layer-toggle`. HRL Toggles in
/// toggle mode produced configs that kanata rejected. The fix adds
/// `layer-toggle` to the scan pattern in `KanataConfiguration+BlockBuilders`.
final class StubDeflayerSafetyNetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func findKanataBinary() -> String? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["KEYPATH_KANATA_PATH"],
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Integration
                .deletingLastPathComponent() // KeyPathTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/kanata")
                .path,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
            "/opt/homebrew/bin/kanata"
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @MainActor
    private func validateWithKanata(_ config: String) async throws -> (isValid: Bool, errors: [String]) {
        guard let binary = findKanataBinary() else {
            throw XCTSkip("Kanata binary not found — skipping CLI validation")
        }
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("stub-deflayer-\(UUID().uuidString).kbd")
        try config.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--cfg", tempFile.path, "--check"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return (true, [])
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let errors = output.components(separatedBy: .newlines)
                .filter { $0.contains("[ERROR]") || $0.contains("help:") }
            return (false, errors)
        }
    }

    // MARK: - HRL Toggles toggle mode (the case that surfaced this fix)

    /// HRL Toggles in toggle mode references `fun`, `sym`, `num` via
    /// `(layer-toggle ...)` actions. Without the safety net these are
    /// orphan references and kanata --check rejects the config.
    @MainActor
    func testHRLTogglesToggleModeAlone_StubLayersEmitted() {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .toggle
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        // The generated config should reference the orphan layers ...
        XCTAssertTrue(config.contains("(layer-toggle fun)"), "Expected (layer-toggle fun) in output")
        XCTAssertTrue(config.contains("(layer-toggle sym)"), "Expected (layer-toggle sym) in output")
        XCTAssertTrue(config.contains("(layer-toggle num)"), "Expected (layer-toggle num) in output")

        // ... AND emit matching stub deflayer blocks so kanata accepts the config.
        XCTAssertTrue(config.contains("(deflayer fun"), "Expected stub (deflayer fun ...) block")
        XCTAssertTrue(config.contains("(deflayer sym"), "Expected stub (deflayer sym ...) block")
        XCTAssertTrue(config.contains("(deflayer num"), "Expected stub (deflayer num ...) block")
    }

    @MainActor
    func testHRLTogglesToggleModeAlone_KanataAccepts() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .toggle
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        let result = try await validateWithKanata(config)
        XCTAssertTrue(
            result.isValid,
            "Stub deflayer safety net should make this kanata-valid. Errors: \(result.errors)"
        )
    }

    // MARK: - whileHeld mode still works (regression guard for the original scanner)

    @MainActor
    func testHRLTogglesWhileHeldMode_KanataAccepts() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .whileHeld
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        let result = try await validateWithKanata(config)
        XCTAssertTrue(
            result.isValid,
            "whileHeld mode was already covered by the original scanner — must still validate. Errors: \(result.errors)"
        )
    }
}

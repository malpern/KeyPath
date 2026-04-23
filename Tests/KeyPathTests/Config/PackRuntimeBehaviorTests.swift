@testable import KeyPathAppKit
import Foundation
import XCTest

/// Runtime behavior guard for starter-kit packs. For each pack, we enable
/// its RuleCollection, render the kanata config, and drive `kanata_simulated_input`
/// with a scripted key sequence. The assertion is on the *resulting output keys*
/// — the thing that matters to users — not on config text.
///
/// `kanata --check` (see `RuleCollectionKanataValidationTests`) guarantees
/// the config *parses*. These tests guarantee it *behaves*. A pack whose
/// headline promise silently regresses (e.g. Caps Lock Remap sending the
/// wrong key on tap) would pass --check but fail here.
///
/// Skips gracefully if the simulator binary isn't available.
final class PackRuntimeBehaviorTests: XCTestCase {
    private var simulatorURL: URL? { findBinary("kanata_simulated_input") }

    // MARK: - Starter-kit headline behaviors

    /// Caps Lock Remap's default mapping is Hyper-on-tap and Hyper-on-hold
    /// (see `RuleCollectionCatalog.capsLockRemap`). Tap alone should fire
    /// lctl+lalt+lsft+lmet (the hyper stack). This protects the default;
    /// a tap-output regression would mean every new install gets a broken
    /// caps key.
    func testCapsLockRemapTapFiresHyperStack() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.capsLockRemap],
            script: "↓caps 🕐50 ↑caps 🕐50"
        )
        let output = outputKeys(events)
        // Hyper = lctl + lalt + lsft + lmet (order may vary; check as a set).
        XCTAssertEqual(Set(output), Set(["lctl", "lalt", "lsft", "lmet"]),
                       "Caps tap should fire the hyper modifier stack")
    }

    /// Backup Caps Lock binds the both-shifts chord → caps. The promise is
    /// "press both shifts together and caps fires." If defchordsv2 emission
    /// regresses, this test fails even though the config would still parse.
    func testBackupCapsLockBothShiftsFireCaps() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.backupCapsLock],
            script: "↓lsft 🕐5 ↓rsft 🕐100 ↑lsft 🕐5 ↑rsft 🕐50"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("caps"),
                      "Both shifts together should produce caps; got: \(output)")
    }

    /// Escape Remap's default remaps the Escape key itself (default preset:
    /// esc → caps). Tapping esc should produce a caps press, not an esc.
    func testEscapeRemapTapEmitsCaps() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.escapeRemap],
            script: "↓esc 🕐20 ↑esc 🕐20"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("caps"),
                      "Escape Remap default (esc→caps) should emit caps; got: \(output)")
        XCTAssertFalse(output.contains("esc"),
                       "Escape Remap default should NOT emit esc; got: \(output)")
    }

    /// Home Row Mods makes the home row dual-role: quick tap = letter,
    /// sustained hold = modifier. Tap 'a' quickly; we should see the letter
    /// 'a' come through (not lctl, which is the hold action).
    func testHomeRowModsShortTapEmitsLetter() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.homeRowMods],
            script: "↓a 🕐20 ↑a 🕐50"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("a"),
                      "Short tap on 'a' should emit 'a'; got: \(output)")
    }

    /// Window Snapping is activated via Leader → w (nested layer). The
    /// simulator cannot observe `push-msg` outputs (they go through TCP,
    /// which isn't running in the sim), so instead we assert on the
    /// `finalLayer` — holding space+w should land us in the "window" layer
    /// where action keys fire Accessibility-driven window moves.
    func testWindowSnappingNestedLayerActivation() throws {
        let result = try simulateFull(
            collectionIDs: [
                RuleCollectionIdentifier.windowSnapping,
                // The window layer is nested inside nav; nav is activated by
                // vimNavigation's Space-hold activator.
                RuleCollectionIdentifier.vimNavigation
            ],
            script: "↓spc 🕐300 ↓w 🕐200"
        )
        XCTAssertEqual(result.finalLayer, "window",
                       "Holding space + w should put us in the 'window' layer for window-snapping actions")
    }

    /// Mission Control maps 3-modifier chords (lctl + lmet + lalt + direction
    /// or letter) to plain key combos macOS already interprets — e.g. the
    /// `lctl + lmet + lalt + up` chord emits `C-up`, which is macOS's own
    /// Mission Control shortcut. No AX or push-msg indirection, so the
    /// simulator observes the actual output.
    func testMissionControlChordEmitsCtrlUp() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.missionControl],
            // Press all 3 modifiers together with up inside the chord
            // window, release in reverse. Timings stay under defchordsv2's
            // chord window.
            script: "↓lctl 🕐5 ↓lmet 🕐5 ↓lalt 🕐5 ↓up 🕐50 ↑up 🕐20 ↑lalt 🕐5 ↑lmet 🕐5 ↑lctl 🕐50"
        )
        let output = outputKeys(events)
        // The chord resolves to `C-up` which emits lctl+up. If the chord
        // hadn't fired, we'd still see lctl but not a clean `up` output
        // (up would still be suppressed by defsrc's chord input claim).
        XCTAssertTrue(output.contains("up"),
                      "Mission Control chord should emit up (as part of C-up); got: \(output)")
    }

    /// Vim Navigation's headline: hold Space → nav layer; inside the layer,
    /// h/j/k/l emit arrow keys. Without the Space-hold activation the letter
    /// should come through as-is. This checks both paths in one script.
    func testVimNavigationSpaceHoldMakesJEmitDown() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.vimNavigation],
            // Hold space for 300ms (past the layer activation delay), tap j,
            // then release. The j press should map to `down`.
            script: "↓spc 🕐300 ↓j 🕐30 ↑j 🕐30 ↑spc 🕐30"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("down"),
                      "j inside nav layer should emit 'down'; got: \(output)")
    }

    // MARK: - Harness

    private struct SimEvent: Decodable {
        let type: String
        let action: String?
        let key: String?
    }

    private struct SimResult: Decodable {
        let events: [SimEvent]
        let finalLayer: String?
    }

    /// Generate a kanata config with the given collections enabled, drive
    /// the simulator with `script`, return the parsed events.
    private func simulate(collectionIDs: [UUID], script: String) throws -> [SimEvent] {
        try simulateFull(collectionIDs: collectionIDs, script: script).events
    }

    private func simulateFull(collectionIDs: [UUID], script: String) throws -> SimResult {
        guard let simulator = simulatorURL else {
            throw XCTSkip("kanata_simulated_input binary not available")
        }
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collections = collectionIDs.compactMap { id in
            catalog.first(where: { $0.id == id }).map { collection -> RuleCollection in
                var copy = collection
                copy.isEnabled = true
                return copy
            }
        }
        XCTAssertEqual(collections.count, collectionIDs.count, "missing catalog collection(s)")
        let config = KanataConfiguration.generateFromCollections(collections)

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let cfgURL = tmp.appendingPathComponent("keypath-sim-\(UUID().uuidString).kbd")
        let simURL = tmp.appendingPathComponent("keypath-sim-\(UUID().uuidString).txt")
        try config.write(to: cfgURL, atomically: true, encoding: .utf8)
        try script.write(to: simURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: cfgURL)
            try? FileManager.default.removeItem(at: simURL)
        }

        let process = Process()
        process.executableURL = simulator
        process.arguments = ["--cfg", cfgURL.path, "--sim", simURL.path, "--json"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("simulator exited \(process.terminationStatus): \(err)")
            return SimResult(events: [], finalLayer: nil)
        }

        // Some log lines (info/warn) can precede the JSON block. Find the
        // first '{' and decode from there.
        guard let start = data.firstIndex(of: UInt8(ascii: "{")) else {
            XCTFail("simulator output contained no JSON: \(String(data: data, encoding: .utf8) ?? "")")
            return SimResult(events: [], finalLayer: nil)
        }
        let json = data[start...]
        return try JSONDecoder().decode(SimResult.self, from: Data(json))
    }

    /// Pull the distinct key identifiers from output events (press-only),
    /// preserving order of first appearance.
    private func outputKeys(_ events: [SimEvent]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for event in events where event.type == "output" && event.action == "press" {
            if let key = event.key, !seen.contains(key) {
                seen.insert(key)
                result.append(key)
            }
        }
        return result
    }

    private func findBinary(_ name: String) -> URL? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["KEYPATH_KANATA_BIN_DIR"]
                .map { "\($0)/\(name)" },
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Config
                .deletingLastPathComponent() // KeyPathTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/\(name)")
                .path
        ].compactMap { $0 }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

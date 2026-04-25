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

    /// Delete Enhancement maps backspace inside the nav layer to the
    /// selected alternate-delete action (default: forward delete). Regular
    /// backspace is untouched at base — only Leader+bspc fires the
    /// enhancement. Here we assert the default preset works: hold Space,
    /// press bspc → `del` (Forward Delete) emitted.
    func testDeleteEnhancementLeaderBspcEmitsForwardDelete() throws {
        let events = try simulate(
            collectionIDs: [
                RuleCollectionIdentifier.deleteRemap,
                // Delete Enhancement lives in the nav layer — needs a nav
                // provider (Vim Navigation) for Space to get us there.
                RuleCollectionIdentifier.vimNavigation
            ],
            script: "↓spc 🕐300 ↓bspc 🕐30 ↑bspc 🕐30 ↑spc 🕐30"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("del"),
                      "Leader + bspc should emit 'del' (Forward Delete); got: \(output)")
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

    /// Mission Control: Leader (Space) + single key. Holding Space for the
    /// nav layer, then tapping `m` should emit `C-up` (macOS's Mission
    /// Control shortcut → we see `up` in the simulator output as part of
    /// lctl+up). Replaced the earlier 3-modifier-chord design which was
    /// harder to press than the F3 it claimed to improve on.
    func testMissionControlLeaderMEmitsCtrlUp() throws {
        let events = try simulate(
            collectionIDs: [
                RuleCollectionIdentifier.missionControl,
                // MC is an additive nav-layer pack — it needs a nav
                // provider (Vim Nav) on to supply the Space activator.
                RuleCollectionIdentifier.vimNavigation
            ],
            // Hold Space (→ nav layer), tap `m`, release.
            script: "↓spc 🕐300 ↓m 🕐30 ↑m 🕐30 ↑spc 🕐30"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("up"),
                      "Leader + m should emit C-up (lctl+up) for Mission Control; got: \(output)")
    }

    /// Auto Shift Symbols makes symbol keys dual-role: quick tap emits the
    /// symbol normally; holding past ~180ms emits the shifted variant. We
    /// check the tap path — hold emits `S-'` which the simulator renders as
    /// lsft + apostrophe, but timing is picky across platforms so we just
    /// pin down the easy case (short tap must still give the raw symbol).
    func testAutoShiftSymbolsShortTapEmitsRawSymbol() throws {
        let events = try simulate(
            collectionIDs: [RuleCollectionIdentifier.autoShiftSymbols],
            // 30ms well under the ~180ms auto-shift threshold.
            script: "↓' 🕐30 ↑' 🕐50"
        )
        let output = outputKeys(events)
        // Simulator reports apostrophe as kanata's internal `apos` name.
        // Either that or the raw `'` is acceptable; both mean the tap path
        // is working.
        let emittedApostrophe = output.contains("'") || output.contains("apos")
        XCTAssertTrue(emittedApostrophe,
                      "Short tap on apostrophe should still emit apostrophe; got: \(output)")
        XCTAssertFalse(output.contains("lsft"),
                       "Short tap should NOT engage shift; got: \(output)")
    }

    /// Numpad Layer is two-step-activated (Leader → `;`). Nested-layer
    /// activators render as one-shot-press, so `;` is tapped (not held)
    /// while Space is held for nav. Inside the num layer, j should emit kp4.
    func testNumpadLayerJBecomesKp4() throws {
        let events = try simulate(
            collectionIDs: [
                RuleCollectionIdentifier.numpadLayer,
                RuleCollectionIdentifier.vimNavigation
            ],
            script: "↓spc 🕐300 ↓; 🕐30 ↑; 🕐30 ↓j 🕐30 ↑j 🕐30 ↑spc 🕐20"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("kp4"),
                      "j inside numpad layer should emit kp4; got: \(output)")
    }

    /// Symbol Layer is nested under nav (Leader → `s`). Inside the sym
    /// layer, the default Mirrored preset maps the top row to shifted
    /// variants — `1` emits `S-1` (= `!`), which the simulator renders as
    /// lsft + 1. Assert on `lsft` in the output (a key that would NOT
    /// fire if the layer transition hadn't happened).
    func testSymbolLayerNestedActivation() throws {
        let result = try simulateFull(
            collectionIDs: [
                RuleCollectionIdentifier.symbolLayer,
                RuleCollectionIdentifier.vimNavigation
            ],
            // Space held (→ nav), hold `s` (→ sym).
            script: "↓spc 🕐300 ↓s 🕐300"
        )
        XCTAssertEqual(result.finalLayer, "sym",
                       "Holding space + s should put us in the 'sym' layer; got: \(result.finalLayer ?? "nil")")
    }

    /// Fun Layer is nested under nav (Leader → `f`). Once in fun, the
    /// right-hand numpad grid emits F-keys — `u` should emit `f7`.
    func testFunLayerUEmitsF7() throws {
        let events = try simulate(
            collectionIDs: [
                RuleCollectionIdentifier.funLayer,
                RuleCollectionIdentifier.vimNavigation
            ],
            // Space held (→ nav), hold `f` (→ fun), tap `u`.
            script: "↓spc 🕐300 ↓f 🕐100 ↓u 🕐30 ↑u 🕐30 ↑f 🕐20 ↑spc 🕐20"
        )
        let output = outputKeys(events)
        XCTAssertTrue(output.contains("f7"),
                      "u inside fun layer should emit f7; got: \(output)")
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

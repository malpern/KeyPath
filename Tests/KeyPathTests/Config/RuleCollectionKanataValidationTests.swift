@testable import KeyPathAppKit
import XCTest

/// Data-driven guard that catches validator-level config bugs (like the
/// `concurrent-tap-hold` / `defchordsv2` coupling) before they ship.
///
/// Strategy: for each catalog collection — and a few known-risky combos —
/// render a full kanata config and run `kanata --check` on the result. The
/// validator knows the kanata grammar rules; we don't need to.
///
/// Cost: ~10-40ms per `--check` invocation. The suite stays under ~2s.
///
/// If the bundled kanata binary isn't available (fresh checkout without a
/// Rust build), the test skips rather than fails — CI environments that
/// need this coverage should build kanata first.
final class RuleCollectionKanataValidationTests: XCTestCase {
    /// Resolve the kanata binary. CI should set `KEYPATH_KANATA_PATH` to an
    /// explicit location; locally we fall back to the repo's debug build.
    private var kanataURL: URL? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["KEYPATH_KANATA_PATH"],
            // Repo-relative fallback (works from any checkout location).
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Config
                .deletingLastPathComponent() // KeyPathTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/kanata")
                .path
        ].compactMap { $0 }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Per-collection

    func testEveryCatalogCollectionValidates() throws {
        guard let kanata = kanataURL else {
            throw XCTSkip("kanata binary not available (set KEYPATH_KANATA_PATH or build External/kanata)")
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        XCTAssertFalse(catalog.isEmpty, "catalog should not be empty")

        for collection in catalog {
            let enabled = collection.withIsEnabled(true)
            let config = KanataConfiguration.generateFromCollections([enabled])
            try assertKanataAccepts(config, kanata: kanata, label: collection.name)
        }
    }

    // MARK: - Risky combinations

    /// Backup Caps Lock emits `defchordsv2`; Home Row Mods emits tap-hold
    /// actions. Kanata requires `concurrent-tap-hold yes` in defcfg when
    /// both exist. This combo caught a real bug.
    func testHomeRowModsPlusChordCollection() throws {
        try validateCombo(named: "HRM + Backup Caps Lock (chord)", ids: [
            RuleCollectionIdentifier.homeRowMods,
            RuleCollectionIdentifier.backupCapsLock
        ])
    }

    func testCapsLockRemapPlusHomeRowMods() throws {
        try validateCombo(named: "Caps Lock Remap + HRM", ids: [
            RuleCollectionIdentifier.capsLockRemap,
            RuleCollectionIdentifier.homeRowMods
        ])
    }

    func testAllProductivityCollectionsTogether() throws {
        try validateCombo(named: "all productivity", ids: [
            RuleCollectionIdentifier.capsLockRemap,
            RuleCollectionIdentifier.backupCapsLock,
            RuleCollectionIdentifier.escapeRemap,
            RuleCollectionIdentifier.deleteRemap,
            RuleCollectionIdentifier.homeRowMods
        ])
    }

    /// Enable every catalog collection at once and run kanata --check on
    /// the resulting config. This catches emergent conflicts between
    /// collections (activator collisions, defcfg option clashes, chord/
    /// tap-hold interactions, etc.) that per-collection tests miss.
    func testEveryCatalogCollectionEnabledAtOnce() throws {
        guard let kanata = kanataURL else {
            throw XCTSkip("kanata binary not available (set KEYPATH_KANATA_PATH or build External/kanata)")
        }
        let catalog = RuleCollectionCatalog().defaultCollections()
        let allEnabled = catalog.map { $0.withIsEnabled(true) }
        let config = KanataConfiguration.generateFromCollections(allEnabled)
        try assertKanataAccepts(config, kanata: kanata, label: "every collection enabled")
    }

    // MARK: - Helpers

    private func validateCombo(named label: String, ids: [UUID]) throws {
        guard let kanata = kanataURL else {
            throw XCTSkip("kanata binary not available (set KEYPATH_KANATA_PATH or build External/kanata)")
        }
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collections: [RuleCollection] = ids.compactMap { id in
            catalog.first(where: { $0.id == id })?.withIsEnabled(true)
        }
        XCTAssertEqual(collections.count, ids.count, "\(label): missing catalog entries")
        let config = KanataConfiguration.generateFromCollections(collections)
        try assertKanataAccepts(config, kanata: kanata, label: label)
    }

    private func assertKanataAccepts(_ config: String, kanata: URL, label: String) throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-validation-\(UUID().uuidString).kbd")
        try config.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = kanata
        process.arguments = ["--cfg", tempURL.path, "--check"]
        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            let out = String(data: outData, encoding: .utf8) ?? ""
            XCTFail("""
                kanata --check rejected config for \(label) (exit \(process.terminationStatus)).
                --- stderr ---
                \(err)
                --- stdout ---
                \(out)
                --- config (first 800 chars) ---
                \(String(config.prefix(800)))
                """)
        }
    }
}

private extension RuleCollection {
    func withIsEnabled(_ value: Bool) -> RuleCollection {
        var copy = self
        copy.isEnabled = value
        return copy
    }
}

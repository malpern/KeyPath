@testable import KeyPathAppKit
import XCTest

final class LayerKeyMapperMissingLayerTests: XCTestCase {
    func testDefinedLayerNamesReadsDeflayerAndDeflayermapAndIgnoresComments() {
        let config = """
        (defsrc a s d)
        (deflayer base a s d)
        (deflayermap (Nav) h left)
        ;; (deflayer window a s d)
        (deflayer num 1 2 3) ;; trailing comment
        """
        XCTAssertEqual(
            LayerKeyMapper.definedLayerNames(inConfig: config, configDirectory: nil),
            ["base", "nav", "num"]
        )
    }

    func testDefinedLayerNamesFollowsIncludes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "(deflayer apps a s d)".write(to: dir.appendingPathComponent("extra.kbd"), atomically: true, encoding: .utf8)

        let names = LayerKeyMapper.definedLayerNames(
            inConfig: "(deflayer base a s d)\n(include extra.kbd)\n(include missing.kbd)",
            configDirectory: dir.path
        )
        XCTAssertEqual(names, ["base", "apps"])
    }

    /// The Air's config had only `base` while the Context HUD precompute asked for `nav`
    /// at every launch: 77 simulator runs, each failing with "unknown layer: nav".
    func testALayerTheConfigDoesNotDefineIsNeverSimulated() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let configPath = dir.appendingPathComponent("keypath.kbd").path
        try "(defsrc a s d)\n(deflayer base a s d)".write(toFile: configPath, atomically: true, encoding: .utf8)

        // A simulator path that does not exist: any simulation attempt would throw and
        // be reported as a failed key.
        let simulator = SimulatorService.forTesting(simulatorPath: dir.appendingPathComponent("no-simulator").path)
        let mapper = LayerKeyMapper(simulatorService: simulator, simulatorEnabled: { true })

        let (mapping, report) = try await mapper.getMapping(for: "nav", configPath: configPath, layout: .macBookUS)
        XCTAssertNil(report, "a missing layer must not produce a failure report (and so no alert)")
        XCTAssertFalse(mapping.isEmpty, "the overlay still gets plain key labels")
    }
}

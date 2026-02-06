import Foundation
@testable import KeyPathAppKit
import Testing

/// Tests for MomentaryActivator Codable backward compatibility
struct MomentaryActivatorCodableTests {
    /// Verify that MomentaryActivator can decode JSON without sourceLayer field (backward compatibility)
    @Test func decodesWithoutSourceLayer() throws {
        // JSON representing an old MomentaryActivator without sourceLayer field
        let oldJSON = """
        {
            "input": "space",
            "targetLayer": "nav"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let activator = try decoder.decode(MomentaryActivator.self, from: oldJSON)

        #expect(activator.input == "space")
        #expect(activator.targetLayer == .navigation)
        #expect(activator.sourceLayer == .base, "sourceLayer should default to .base when missing")
    }

    /// Verify that MomentaryActivator can decode JSON with sourceLayer field (new format)
    @Test func decodesWithSourceLayer() throws {
        let newJSON = """
        {
            "input": "space",
            "targetLayer": "nav",
            "sourceLayer": "navigation"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let activator = try decoder.decode(MomentaryActivator.self, from: newJSON)

        #expect(activator.input == "space")
        #expect(activator.targetLayer == .navigation)
        #expect(activator.sourceLayer == .navigation, "sourceLayer should be decoded when present")
    }

    /// Verify that MomentaryActivator encodes all fields including sourceLayer
    @Test func encodesWithSourceLayer() throws {
        let activator = MomentaryActivator(
            input: "space",
            targetLayer: .navigation,
            sourceLayer: .navigation
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(activator)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"input\""))
        #expect(json.contains("\"targetLayer\""))
        #expect(json.contains("\"sourceLayer\""))
        #expect(json.contains("\"space\""))
        #expect(json.contains("\"nav\""))
    }

    /// Verify that encoding/decoding round-trip preserves all fields
    @Test func roundTripEncoding() throws {
        let original = MomentaryActivator(
            input: "space",
            targetLayer: .navigation,
            sourceLayer: .navigation
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MomentaryActivator.self, from: data)

        #expect(decoded.input == original.input)
        #expect(decoded.targetLayer == original.targetLayer)
        #expect(decoded.sourceLayer == original.sourceLayer)
    }
}

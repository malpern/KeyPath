import Foundation
import Testing
@testable import KeyPathLayoutTracerKit

struct LayoutTracerExporterTests {
    @Test
    func exportProducesKeyPathCompatibleShape() throws {
        let keys = [
            TracingKey(keyCode: 12, label: "Q", x: 10, y: 20, width: 50, height: 40),
            TracingKey(keyCode: 13, label: "W", x: 70, y: 20, width: 50, height: 40)
        ]

        let data = try LayoutTracerExporter.export(
            id: "test-layout",
            name: "Test Layout",
            keys: keys,
            totalWidth: 800,
            totalHeight: 300
        )

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["id"] as? String == "test-layout")
        #expect(json?["name"] as? String == "Test Layout")
        let exportedKeys = json?["keys"] as? [[String: Any]]
        #expect(exportedKeys?.count == 2)
        #expect(json?["totalWidth"] as? Double == 800)
        #expect(json?["totalHeight"] as? Double == 300)
    }

    @Test
    func importRoundTripsExportedLayout() throws {
        let original = [
            TracingKey(keyCode: 49, label: "space", x: 120, y: 340, width: 180, height: 56),
            TracingKey(keyCode: 51, label: "⌫", x: 980, y: 120, width: 72, height: 118)
        ]

        let data = try LayoutTracerExporter.export(
            id: "kinesis-mwave",
            name: "Kinesis mWave",
            keys: original,
            totalWidth: 1400,
            totalHeight: 640
        )
        let imported = try LayoutTracerImporter.load(from: data)

        #expect(imported.id == "kinesis-mwave")
        #expect(imported.name == "Kinesis mWave")
        #expect(imported.totalWidth == 1400)
        #expect(imported.totalHeight == 640)
        #expect(imported.keys.count == 2)
        #expect(imported.keys.contains(where: { $0.label == "space" && $0.keyCode == 49 }))
        #expect(imported.keys.contains(where: { $0.label == "⌫" && $0.keyCode == 51 }))
    }
}

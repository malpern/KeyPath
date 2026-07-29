@testable import KeyPathAppKit
import XCTest

final class KeyboardStageTuningTests: XCTestCase {
    func testPartialJSONKeepsShippedDefaultsForOmittedKeys() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-tuning-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"grazeAmplitudeDeck": 0.3, "unknownKey": 12}"#.utf8)
            .write(to: url)

        let tuning = try KeyboardStageTuning.load(from: url)

        XCTAssertEqual(tuning.grazeAmplitudeDeck, 0.3, accuracy: 0.0001)
        XCTAssertEqual(
            tuning.rimDirectionalityPeak,
            KeyboardStageTuning.default.rimDirectionalityPeak,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            tuning.legendEmissionMax,
            KeyboardStageTuning.default.legendEmissionMax,
            accuracy: 0.0001
        )
    }

    func testGPUVectorsPackTheDocumentedLanes() {
        let tuning = KeyboardStageTuning.default

        XCTAssertEqual(tuning.gpuVectorA.x, tuning.grazeAmplitudeDeck)
        XCTAssertEqual(tuning.gpuVectorB.y, tuning.rimDirectionalityPeak)
        XCTAssertEqual(tuning.gpuVectorC.w, tuning.backlightStrengthDark)
        XCTAssertEqual(tuning.gpuVectorD.y, tuning.legendEmissionMax)
    }

    func testEnvironmentFileURLExpandsTilde() {
        XCTAssertNil(KeyboardStageTuning.environmentFileURL)
    }
}

import Foundation
import Testing
@testable import KeyPathLayoutTracerKit

struct LayoutAnalysisImporterTests {
    @Test
    func importsAnalysisLayerJSON() throws {
        let payload = """
        {
          "imageSize": { "width": 1200, "height": 500 },
          "modelVersion": "opencv-contour",
          "proposals": [
            {
              "confidence": 0.82,
              "height": 40,
              "id": "proposal-1",
              "rotation": 5,
              "source": "opencv-contour",
              "width": 50,
              "x": 10,
              "y": 20
            }
          ],
          "sourceImage": "/tmp/example.png"
        }
        """.data(using: .utf8)!

        let analysis = try LayoutAnalysisImporter.load(from: payload)

        #expect(analysis.modelVersion == "opencv-contour")
        #expect(analysis.proposals.count == 1)
        #expect(analysis.proposals[0].rotation == 5)
    }
}

import Foundation

struct LayoutAnalysisProposal: Identifiable, Codable, Equatable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let confidence: Double
    let source: String

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func asTracingKey(index: Int) -> TracingKey {
        TracingKey(
            keyCode: 0,
            label: "K\(index)",
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: abs(rotation) < 0.001 ? nil : rotation
        )
    }
}

struct LayoutAnalysisImageSize: Codable, Equatable {
    let width: Double
    let height: Double
}

struct LayoutAnalysisDocument: Codable, Equatable {
    let sourceImage: String
    let imageSize: LayoutAnalysisImageSize
    let modelVersion: String
    let proposals: [LayoutAnalysisProposal]
}

enum LayoutAnalysisImporter {
    static func load(from data: Data) throws -> LayoutAnalysisDocument {
        try JSONDecoder().decode(LayoutAnalysisDocument.self, from: data)
    }
}

import Foundation
@testable import KeyPathRulesCore
@preconcurrency import XCTest

/// Generated config must be the same bytes in every language, so names written
/// into config comments come from `configName`, never the localized `displayName`.
final class ConfigTextIsNotLocalizedTests: XCTestCase {
    func testLayerConfigNamesAreFixedEnglish() {
        XCTAssertEqual(RuleCollectionLayer.base.configName, "Base")
        XCTAssertEqual(RuleCollectionLayer.navigation.configName, "Navigation")
        XCTAssertEqual(RuleCollectionLayer.custom("window").configName, "Window")
    }

    func testConfigRenderingDoesNotUseLocalizedLayerNames() throws {
        let configDir = LintScanner.path("Sources/KeyPathAppKit/Infrastructure/Config")
        let files = try FileManager.default.contentsOfDirectory(atPath: configDir.path)
            .filter { $0.hasPrefix("KanataConfiguration") && $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: configDir.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("Layer.displayName"), "\(file) writes a localized layer name into config")
        }
    }
}

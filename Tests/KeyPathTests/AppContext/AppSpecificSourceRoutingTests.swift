import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class AppSpecificSourceRoutingTests: XCTestCase {
    func testAppOnlyInputsAreCapturedAndRoutedOnceAcrossPhysicalLayouts() throws {
        for layout in [PhysicalLayout.macBookUS, .macBookJIS, .macBookISO] {
            let content = KanataConfiguration.generateFromCollections(
                [], inputs: KanataGenerationInputs(appSpecificKeys: ["a", "c"], physicalLayout: layout)
            )
            let source = try blockTokens("defsrc", in: content)
            let base = try blockTokens("deflayer base", in: content)
            for key in ["a", "c"] {
                XCTAssertEqual(source.filter { $0 == key }.count, 1, layout.id)
                XCTAssertEqual(base.filter { $0 == "@kp-\(key)" }.count, 1, layout.id)
            }
            XCTAssertEqual(source.count, base.count)
        }
    }

    func testGeneratedAppOnlySwitchIsValidatedWithEveryNestedOutput() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-only-routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("candidate.kbd")
        let main = KanataConfiguration.generateFromCollections(
            [], inputs: KanataGenerationInputs(appSpecificKeys: ["c"])
        )
        let usages = Array(SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 })
        for (output, expectedValid) in [
            ("d", true),
            ("(switch ((input virtual vk_test_app)) (unicode ä) break () d break)", false),
            ("volu", false)
        ] {
            let keymap = AppKeymap(bundleIdentifier: "test.app", displayName: "Test App", overrides: [
                AppKeyOverride(inputKey: "c", action: .rawKanata(output))
            ])
            // Use the actual generated virtual key name in the nested expression.
            let include = AppConfigGenerator.generate(from: [keymap])
                .replacingOccurrences(of: "vk_test_app", with: keymap.mapping.virtualKeyName)
            XCTAssertTrue(include.contains("() c break)"), "App-only fallback must preserve the input")
            let candidate = main.replacingOccurrences(of: "(include keypath-apps.kbd)", with: include)
            try candidate.write(to: path, atomically: true, encoding: .utf8)
            XCTAssertEqual(KanataHostBridge.validateConfig(runtimeHost: SessionBridgeTestFixture.runtimeHost, configPath: path.path), .valid)
            let result = KanataHostBridge.validateSessionConfig(
                runtimeHost: SessionBridgeTestFixture.runtimeHost, configPath: path.path, supportedUsages: usages
            )
            if expectedValid {
                XCTAssertEqual(result, .valid)
            } else if case .invalid = result {
                // A rejected parsed branch must reach the save transaction gate.
            } else {
                XCTFail("Unsupported generated app output was admitted: \(result)")
            }
        }
    }

    private func blockTokens(_ name: String, in content: String) throws -> [String] {
        let range = try XCTUnwrap(content.range(of: "(?m)^\\(\(name)(?=\\s)", options: .regularExpression))
        let remaining = content[range.upperBound...]
        let end = try XCTUnwrap(remaining.firstIndex(of: ")"))
        return remaining[..<end].split(separator: "\n").flatMap { line in
            line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .split(whereSeparator: \.isWhitespace).map(String.init)
        }
    }
}

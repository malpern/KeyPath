import Foundation
@preconcurrency import XCTest

/// Every language the app declares must translate the permission prompts macOS
/// shows from the main bundle, or those prompts appear in English (P8).
final class AppLocalizationsContractTests: XCTestCase {
    func testEveryDeclaredLanguageTranslatesEveryUsageDescription() throws {
        let app = LintScanner.path("Sources/KeyPathApp")
        let data = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let languages = try XCTUnwrap(info["CFBundleLocalizations"] as? [String])
        XCTAssertTrue(languages.contains("en"))
        XCTAssertTrue(languages.contains("ja"))
        let usageKeys = Set(info.keys.filter { $0.hasSuffix("UsageDescription") })
        XCTAssertFalse(usageKeys.isEmpty)

        for language in languages {
            let url = app.appendingPathComponent("Resources/\(language).lproj/InfoPlist.strings")
            let strings = try XCTUnwrap(
                NSDictionary(contentsOf: url) as? [String: String],
                "\(language).lproj/InfoPlist.strings is missing or unreadable"
            )
            XCTAssertEqual(Set(strings.keys).intersection(usageKeys), usageKeys,
                           "\(language) is missing a permission prompt translation")
        }
    }
}

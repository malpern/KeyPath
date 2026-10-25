import Foundation
@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import XCTest

final class KeyPathInstallationWizardResourcesTests: XCTestCase {
    func testDriverApprovalScreenshotResolvesThroughPackagedResourceContract() {
        XCTAssertNotNil(
            KeyPathInstallationWizardResources.bundle.url(
                forResource: "karabiner-driver-extension-switch",
                withExtension: "png"
            )
        )
    }

    func testExplicitResolversFindResourcesInPackagedAppLayout() throws {
        let fixture = try PackagedResourceBundleFixture()
        defer { fixture.remove() }

        let appKitBundle = KeyPathAppKitResources.resolveBundle(
            mainBundle: fixture.appBundle,
            codeBundle: fixture.appBundle
        )
        let wizardBundle = KeyPathInstallationWizardResources.resolveBundle(
            mainBundle: fixture.appBundle,
            codeBundle: fixture.appBundle
        )

        XCTAssertEqual(
            appKitBundle.bundleURL.standardizedFileURL,
            fixture.bundleURL(named: "KeyPath_KeyPathAppKit.bundle").standardizedFileURL
        )
        XCTAssertNotNil(appKitBundle.url(forResource: "packaged-probe", withExtension: "txt"))
        XCTAssertEqual(
            wizardBundle.bundleURL.standardizedFileURL,
            fixture.bundleURL(named: "KeyPath_KeyPathInstallationWizard.bundle").standardizedFileURL
        )
        XCTAssertNotNil(wizardBundle.url(forResource: "packaged-probe", withExtension: "txt"))
    }
}

private struct PackagedResourceBundleFixture {
    let rootURL: URL
    let appBundle: Bundle

    init() throws {
        let fileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("keypath-packaged-resources-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("KeyPath.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: contentsURL.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.packaged-resources",
            packageType: "APPL"
        )

        for name in ["KeyPath_KeyPathAppKit.bundle", "KeyPath_KeyPathInstallationWizard.bundle"] {
            let bundleURL = resourcesURL.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            try Self.writeInfoPlist(
                to: bundleURL.appendingPathComponent("Info.plist"),
                identifier: "com.keypath.tests.\(name)",
                packageType: "BNDL"
            )
            try Data("packaged".utf8).write(
                to: bundleURL.appendingPathComponent("packaged-probe.txt")
            )
        }

        appBundle = try XCTUnwrap(Bundle(url: appURL))
    }

    func bundleURL(named name: String) -> URL {
        rootURL
            .appendingPathComponent("KeyPath.app/Contents/Resources", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeInfoPlist(
        to url: URL,
        identifier: String,
        packageType: String
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": identifier,
                "CFBundleName": "KeyPath Resource Fixture",
                "CFBundlePackageType": packageType,
                "CFBundleVersion": "1",
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}

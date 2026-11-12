import Foundation
@testable import KeyPathAppKit
import XCTest

final class KeyPathAppKitResourcesTests: XCTestCase {
    func testResolverFindsResourcesInPackagedAppLayout() throws {
        let fixture = try PackagedResourceBundleFixture()
        defer { fixture.remove() }

        let appKitBundle = KeyPathAppKitResources.resolveBundle(
            mainBundle: fixture.appBundle,
            codeBundle: fixture.appBundle
        )
        XCTAssertEqual(
            appKitBundle.bundleURL.standardizedFileURL,
            fixture.resourceBundleURL.standardizedFileURL
        )
        XCTAssertNotNil(appKitBundle.url(forResource: "packaged-probe", withExtension: "txt"))
    }
}

private struct PackagedResourceBundleFixture {
    let rootURL: URL
    let appBundle: Bundle
    let resourceBundleURL: URL

    init() throws {
        let fileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("keypath-packaged-resources-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("KeyPath.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        resourceBundleURL = resourcesURL.appendingPathComponent("KeyPath_KeyPathAppKit.bundle", isDirectory: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: contentsURL.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.packaged-resources",
            packageType: "APPL"
        )

        try fileManager.createDirectory(at: resourceBundleURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(
            to: resourceBundleURL.appendingPathComponent("Info.plist"),
            identifier: "com.keypath.tests.appkit-resources",
            packageType: "BNDL"
        )
        try Data("packaged".utf8).write(
            to: resourceBundleURL.appendingPathComponent("packaged-probe.txt")
        )

        appBundle = try XCTUnwrap(Bundle(url: appURL))
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

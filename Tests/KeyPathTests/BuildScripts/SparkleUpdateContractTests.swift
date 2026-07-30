import Foundation
@preconcurrency import XCTest

final class SparkleUpdateContractTests: XCTestCase {
    private let releasedPublicKey = "Jry+V9z0EbEysm5FWpbL8J3XfeFnzWqGI3Y3+CQiHgo="

    func testSparkleDependencyIsPinnedToCurrentRelease() throws {
        let root = repositoryRoot()
        let manifest = try contents(of: root.appendingPathComponent("Package.swift"))
        let resolvedData = try Data(contentsOf: root.appendingPathComponent("Package.resolved"))
        let resolved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: resolvedData) as? [String: Any]
        )
        let pins = try XCTUnwrap(resolved["pins"] as? [[String: Any]])
        let sparkle = try XCTUnwrap(pins.first { $0["identity"] as? String == "sparkle" })
        let state = try XCTUnwrap(sparkle["state"] as? [String: Any])

        XCTAssertTrue(manifest.contains(#"from: "2.9.4""#))
        XCTAssertEqual(state["version"] as? String, "2.9.4")
    }

    func testHardenedSparkleConfigurationIsEnabledWithoutProfiling() throws {
        let plist = try propertyList(
            at: repositoryRoot().appendingPathComponent("Sources/KeyPathApp/Info.plist")
        )

        XCTAssertEqual(plist["SUPublicEDKey"] as? String, releasedPublicKey)
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(plist["SUEnableSystemProfiling"] as? Bool, false)
    }

    func testCommittedFeedIsSignedAndHistoricalBetaIsOnBetaChannel() throws {
        let appcast = try contents(of: repositoryRoot().appendingPathComponent("appcast.xml"))

        XCTAssertTrue(appcast.contains("sparkle-sign-warning"))
        XCTAssertTrue(appcast.contains("sparkle-signatures:"))
        XCTAssertTrue(appcast.contains("<sparkle:channel>beta</sparkle:channel>"))
        XCTAssertFalse(appcast.contains("KeyPath-1.0.0.zip"), "Do not advertise an unpublished stable release.")
    }

    func testReleaseScriptsGenerateAndPublishWholeSignedFeed() throws {
        let root = repositoryRoot()
        let sparkleLibrary = try contents(of: root.appendingPathComponent("Scripts/lib/sparkle.sh"))
        let buildAndSign = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))
        let releaseDoctor = try contents(of: root.appendingPathComponent("Scripts/release-doctor.sh"))
        let release = try contents(of: root.appendingPathComponent("Scripts/release.sh"))

        XCTAssertTrue(sparkleLibrary.contains("KEYPATH_SPARKLE_ACCOUNT=\"${KEYPATH_SPARKLE_ACCOUNT:-keypath}\""))
        XCTAssertTrue(sparkleLibrary.contains("KEYPATH_SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(sparkleLibrary.contains("Curve25519.Signing.PrivateKey"))
        XCTAssertTrue(sparkleLibrary.contains("sops -d \"$secrets_file\""))
        XCTAssertTrue(sparkleLibrary.contains("--ed-key-file -"))
        XCTAssertFalse(sparkleLibrary.contains("--ed-key-file \"$KEYPATH_SPARKLE_PRIVATE_KEY\""))
        XCTAssertTrue(buildAndSign.contains("keypath_run_generate_appcast"))
        XCTAssertTrue(buildAndSign.contains("--channel beta"))
        XCTAssertTrue(buildAndSign.contains("--phased-rollout-interval 86400"))
        XCTAssertTrue(buildAndSign.contains("keypath_verify_sparkle_feed"))
        XCTAssertFalse(buildAndSign.contains("appcast-entry.xml"))
        let sparkleCall = try XCTUnwrap(buildAndSign.range(of: "\ncreate_sparkle_archive\n"))
        let deploymentGuard = try XCTUnwrap(buildAndSign.range(of: #"if [ "${SKIP_DEPLOY:-0}" = "1" ]; then"#))
        XCTAssertLessThan(
            buildAndSign.distance(from: buildAndSign.startIndex, to: sparkleCall.lowerBound),
            buildAndSign.distance(from: buildAndSign.startIndex, to: deploymentGuard.lowerBound),
            "Sparkle artifacts must be generated before the non-deploying build exits."
        )
        XCTAssertTrue(releaseDoctor.contains("keypath_verify_sparkle_signing_identity"))
        XCTAssertTrue(releaseDoctor.contains("keypath_verify_sparkle_feed"))
        XCTAssertTrue(release.contains(#"SPARKLE_APPCAST="dist/sparkle/appcast.xml""#))
        XCTAssertTrue(release.contains(#"ditto "$SPARKLE_APPCAST" appcast.xml"#))
        XCTAssertTrue(release.contains("KEYPATH_RELEASE_BUILD_NUMBER"))
        XCTAssertTrue(release.contains(#"Set :CFBundleVersion $RELEASE_BUILD_NUMBER"#))
        XCTAssertFalse(release.contains(#"Set :CFBundleVersion $NEW_VERSION"#))
        XCTAssertFalse(release.contains("Could not find marker in appcast.xml"))
        XCTAssertFalse(releaseDoctor.contains("ALLOW_UNSIGNED_SPARKLE"))
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // BuildScripts
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

private func propertyList(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return try XCTUnwrap(value as? [String: Any])
}

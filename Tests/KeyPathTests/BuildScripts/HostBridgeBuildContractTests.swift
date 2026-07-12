import Foundation
@preconcurrency import XCTest

final class HostBridgeBuildContractTests: XCTestCase {
    func testHostBridgeCacheTracksReleaseToolchainAndRuntimeLoadability() throws {
        let root = repositoryRoot()
        let buildScript = try contents(of: root.appendingPathComponent("Scripts/build-kanata-host-bridge.sh"))
        let releaseScript = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))

        XCTAssertTrue(buildScript.contains("calculate_build_fingerprint"))
        XCTAssertTrue(buildScript.contains("rustc --version --verbose"))
        XCTAssertTrue(buildScript.contains("cargo --version"))
        XCTAssertTrue(buildScript.contains("xcrun ld -v"))
        XCTAssertTrue(buildScript.contains(#"${DEVELOPER_DIR:-<unset>}"#))
        XCTAssertTrue(buildScript.contains(#"features=%s\n"#))
        XCTAssertTrue(buildScript.contains(#"target=%s\n"#))
        XCTAssertTrue(
            buildScript.contains("--package keypath-kanata-host-bridge"),
            "A toolchain fingerprint miss must force Cargo to relink the final cdylib."
        )

        XCTAssertTrue(
            buildScript.contains(#"python3 "$BRIDGE_VERIFY_SCRIPT""#),
            "The cache and newly linked artifact must pass a real dlopen/API check."
        )
        XCTAssertTrue(
            buildScript.contains("Cached host bridge failed its load check; rebuilding"),
            "A corrupt cache entry must be rebuilt instead of entering a release bundle."
        )
        XCTAssertTrue(
            buildScript.contains("Host bridge failed its load check; refusing to cache or package it"),
            "A newly linked but unloadable bridge must stop release assembly explicitly."
        )
        XCTAssertTrue(
            releaseScript.contains("./Scripts/build-kanata-host-bridge.sh &"),
            "The guarded host-bridge builder must remain part of the signed release path."
        )
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

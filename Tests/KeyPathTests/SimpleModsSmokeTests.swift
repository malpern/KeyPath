@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class SimpleModsSmokeTests: XCTestCase {
    private static let tcpTestsEnabled =
        ProcessInfo.processInfo.environment["KEYPATH_ENABLE_TCP_TESTS"] == "1"

    func testSaveShowsDurationViaStatus() async throws {
        guard Self.tcpTestsEnabled else {
            throw XCTSkip("TCP integration tests disabled (set KEYPATH_ENABLE_TCP_TESTS=1 to enable).")
        }
        // Precondition: Kanata TCP server is running on default port
        let client = KanataTCPClient(port: 37001)
        let ready = await client.checkServerStatus()
        try XCTSkipUnless(
            ready, "Kanata TCP server not ready; Wizard should be all green before running this test."
        )

        // Use user's config path (same as app)
        let configPath = "\(NSHomeDirectory())/.config/keypath/keypath.kbd"
        let service = SimpleModsService(configPath: configPath)

        // Load current mappings
        try? service.load()

        // Pick a simple mapping unlikely to already exist; fall back if needed
        let candidateMappings = [("f1", "f2"), ("2", "3"), ("caps", "escape")]
        var added = false
        for (fromKey, toKey) in candidateMappings
            where !service.installedMappings.contains(where: { $0.fromKey == fromKey && $0.toKey == toKey })
        {
            service.addMapping(fromKey: fromKey, toKey: toKey)
            added = true
            break
        }
        XCTAssertTrue(added, "Could not find a mapping candidate to add")

        // Wait for debounce apply to write the file
        try? await Task.sleep(for: .milliseconds(600)) // 600ms

        // Trigger engine reload with wait semantics
        let reload = await client.reloadConfig(timeoutMs: 3000)
        switch reload {
        case .success:
            break
        default:
            XCTFail("Reload did not succeed: \(reload)")
        }

        // Fetch status; expect last_reload duration to be present for UI toast
        let status = try await client.getStatus()
        XCTAssertTrue(
            status.last_reload?.duration_ms != nil,
            "Expected last_reload.duration_ms to be present for UI toast"
        )
    }
}

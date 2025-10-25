import XCTest
@testable import KeyPath

final class CommunicationSnapshotTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        // Redirect HOME so CommunicationSnapshot writes under a temp tree
        setenv("HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        // Best-effort cleanup
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testTokenPathResolvesUnderHome() {
        let path = CommunicationSnapshot.tcpAuthTokenPath()
        XCTAssertTrue(path.contains(tempHome.path))
        XCTAssertTrue(path.hasSuffix(".config/keypath/tcp-auth-token"))
    }

    func testWriteReadSharedToken() throws {
        let token = "abc123"
        XCTAssertTrue(CommunicationSnapshot.writeSharedTCPToken(token))
        let readBack = CommunicationSnapshot.readSharedTCPToken()
        XCTAssertEqual(readBack, token)
    }

    func testEnsureSharedTCPTokenGeneratesFile() {
        // Ensure no file exists first
        let tokenPath = CommunicationSnapshot.tcpAuthTokenPath()
        try? FileManager.default.removeItem(atPath: tokenPath)

        let token = CommunicationSnapshot.ensureSharedTCPToken()
        XCTAssertFalse(token.isEmpty)
        // Should now exist on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokenPath))
    }

    func testSnapshotHelpers() {
        let snapshot = PreferencesService.communicationSnapshot()
        // Defaults expect TCP enabled, default port, not empty session timeout
        XCTAssertTrue((1024...65535).contains(snapshot.tcpPort))
        // Token may be empty (fresh env) or ensured by earlier tests
        _ = snapshot.communicationLaunchArguments
        _ = snapshot.communicationEnvironmentVariables
    }
}


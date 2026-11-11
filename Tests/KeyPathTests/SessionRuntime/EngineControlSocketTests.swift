import Darwin
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

/// ADR-046: the engine's control socket and the owner-exit watch.
final class EngineControlSocketTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Short on purpose: sun_path holds 104 bytes.
        root = URL(fileURLWithPath: "/tmp/kp-ecs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPrimaryPathIsUsedWhenItFits() throws {
        let primary = root.appendingPathComponent("control")
        let chosen = try EngineControlSocket.choosePath(name: "e-1.sock", primary: primary, fallback: nil)
        XCTAssertEqual(chosen.directory, primary)
        XCTAssertEqual(chosen.path, primary.appendingPathComponent("e-1.sock").path)
    }

    /// A long home directory pushes the primary path past sun_path.
    func testLongPrimaryPathFallsBack() throws {
        let long = root.appendingPathComponent(String(repeating: "h", count: 120))
        let fallback = root.appendingPathComponent("t")
        let chosen = try EngineControlSocket.choosePath(name: "e-1.sock", primary: long, fallback: fallback)
        XCTAssertEqual(chosen.directory, fallback)
        XCTAssertLessThan(chosen.path.utf8.count, EngineControlSocket.sunPathCapacity)
    }

    func testBothPathsTooLongIsAClearError() {
        let long = root.appendingPathComponent(String(repeating: "h", count: 120))
        XCTAssertThrowsError(try EngineControlSocket.choosePath(name: "e-1.sock", primary: long, fallback: long)) {
            XCTAssertEqual($0 as? EngineControlSocket.SetupError, .pathTooLong)
        }
    }

    func testDirectoryIsCreatedPrivate() throws {
        let directory = root.appendingPathComponent("control")
        try EngineControlSocket.prepareDirectory(directory)
        var info = stat()
        XCTAssertEqual(lstat(directory.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o700)
    }

    /// A symlink planted where the directory should be is refused, not followed.
    func testSymlinkInPlaceOfTheDirectoryIsRefused() throws {
        let target = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("control")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try EngineControlSocket.prepareDirectory(link))
    }

    func testSocketIsCreatedOwnerOnlyAndListens() throws {
        let listener = try EngineControlSocket.open(pid: 4242, primary: root.appendingPathComponent("c"), fallback: nil)
        defer { close(listener.fd) }
        var info = stat()
        XCTAssertEqual(lstat(listener.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertTrue(listener.path.hasSuffix("/e-4242.sock"))
    }

    func testStaleSocketsOfDeadWorkersAreRemovedAndOthersKept() throws {
        let directory = root.appendingPathComponent("c")
        let dead = try EngineControlSocket.open(pid: 111, primary: directory, fallback: nil)
        close(dead.fd)
        let live = try EngineControlSocket.open(pid: 222, primary: directory, fallback: nil)
        defer { close(live.fd) }
        let notASocket = directory.appendingPathComponent("e-333.sock").path
        FileManager.default.createFile(atPath: notASocket, contents: Data())

        EngineControlSocket.removeStaleSockets(in: directory) { $0 == 222 }

        XCTAssertFalse(FileManager.default.fileExists(atPath: dead.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notASocket))
    }

    func testThisProcessHasAPIDVersion() {
        XCTAssertNotNil(EngineControlSocket.currentPIDVersion())
    }

    /// The launch passes exactly what the worker's peer check compares.
    func testLaunchArgumentsCarryTheOwnersPIDVersion() {
        let arguments = ServiceLifecycleCoordinator.sessionLaunchArguments(
            capabilitiesOnly: false, reportPath: "/tmp/r", nonce: UUID().uuidString,
            ownerPID: 77, ownerPIDVersion: 9, port: 37001, configPath: "/tmp/c.kbd"
        )
        let index = arguments.firstIndex(of: "--session-owner-pidversion")
        XCTAssertEqual(index.map { arguments[$0 + 1] }, "9")
    }

    // MARK: - Owner exit

    func testExitWatchFiresWhenTheOwnerExits() throws {
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/sleep")
        owner.arguments = ["30"]
        try owner.run()
        let exited = expectation(description: "owner exit observed")
        let watch = SessionOwnerExitSource.watch(pid: owner.processIdentifier) { exited.fulfill() }
        owner.terminate()
        wait(for: [exited], timeout: 5)
        withExtendedLifetime(watch) {}
    }

    /// Registering after the owner is already gone (ESRCH) counts as its exit.
    func testExitWatchFiresAtOnceForAnOwnerThatIsAlreadyGone() throws {
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try owner.run()
        owner.waitUntilExit()
        let exited = expectation(description: "already-exited owner observed")
        exited.assertForOverFulfill = true
        let watch = SessionOwnerExitSource.watch(pid: owner.processIdentifier) { exited.fulfill() }
        wait(for: [exited], timeout: 5)
        withExtendedLifetime(watch) {}
    }
}

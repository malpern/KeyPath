import Darwin
import Foundation
@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class RuntimeControlTests: XCTestCase {
    private var directory: URL!
    private var server: RuntimeControlServer!

    override func setUp() async throws {
        // Short path: sockaddr_un holds ~104 bytes.
        directory = URL(fileURLWithPath: "/tmp/kp-rc-\(UUID().uuidString.prefix(8))", isDirectory: true)
        server = RuntimeControlServer()
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private var socketPath: String {
        directory.appendingPathComponent("runtime.sock").path
    }

    private func response(_ operation: RuntimeControl.Operation, state: RuntimeControl.State) -> RuntimeControl.Response {
        .init(ok: true, operation: operation, state: state, workerPID: state == .running ? 42 : nil, failure: nil,
              lastError: nil, layer: "base", appPID: getpid(), appVersion: "test")
    }

    private func send(_ operation: RuntimeControl.Operation) async throws -> RuntimeControl.Response {
        let path = socketPath
        return try await Task.detached { try RuntimeControl.send(.init(operation: operation), timeout: 5, socketPath: path) }.value
    }

    func testRequestsReachTheHandlerAndAnswersComeBack() async throws {
        var seen: [RuntimeControl.Operation] = []
        server.start(directory: directory) { request in
            seen.append(request.operation)
            return self.response(request.operation, state: request.operation == .stop ? .stopped : .running)
        }
        let status = try await send(.status)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.workerPID, 42)
        let stopped = try await send(.stop)
        XCTAssertEqual(stopped.operation, .stop)
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(seen, [.status, .stop])
    }

    func testSocketIsPrivateToThisUser() {
        server.start(directory: directory) { self.response($0.operation, state: .running) }
        var info = stat()
        XCTAssertEqual(lstat(directory.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o700)
        XCTAssertEqual(lstat(socketPath, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(info.st_mode & 0o077, 0, "no group or other access")
    }

    func testNoAppMeansAppNotRunning() async {
        do {
            _ = try await send(.status)
            XCTFail("Nothing is listening")
        } catch {
            XCTAssertEqual(error as? RuntimeControl.ClientError, .appNotRunning)
        }
    }

    func testStaleSocketFromACrashIsReplaced() async throws {
        let stale = RuntimeControlServer()
        stale.start(directory: directory) { self.response($0.operation, state: .stopped) }
        // A crash leaves the socket file behind with nobody listening.
        stale.stop()
        server.start(directory: directory) { self.response($0.operation, state: .running) }
        let answer = try await send(.status)
        XCTAssertEqual(answer.state, .running)
    }

    func testHandlerMapsRuntimeStatusToResponseStates() {
        let cases: [(ServiceLifecycleCoordinator.RuntimeStatus, RuntimeControl.State, Int?, String?)] = [
            (.running(pid: 7), .running, 7, nil), (.starting, .starting, nil, nil), (.stopped, .stopped, nil, nil),
            (.failed(reason: "held keys"), .failed, nil, "held keys"), (.unknown, .unknown, nil, nil),
        ]
        for (status, state, pid, failure) in cases {
            let response = RuntimeControlHandler.response(ok: true, operation: .status, status: status, lastError: nil)
            XCTAssertEqual(response.state, state)
            XCTAssertEqual(response.workerPID, pid)
            XCTAssertEqual(response.failure, failure)
        }
    }
}

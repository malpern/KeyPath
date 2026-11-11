import Darwin
@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

/// ADR-046: the engine admits only the app that launched it, so the CLI's engine
/// commands are runtime-control requests the app answers. These tests stand in a
/// fake app on a socket and check what the facade asks and how it reads answers.
final class ConfigFacadeEngineViaAppTests: XCTestCase {
    /// Serves one canned response per connection and records each request.
    /// One per test: its answers can change, and only its own thread closes its
    /// socket, so a stopped fake can never pick up a later fake's connections.
    private final class FakeApp: @unchecked Sendable {
        typealias Respond = @Sendable (RuntimeControl.Request) -> RuntimeControl.Response
        let path: String
        private let fd: Int32
        private let lock = NSLock()
        private var requests: [RuntimeControl.Request] = []
        private var respond: Respond
        private var stopped = false

        init(respond: @escaping Respond) throws {
            self.respond = respond
            let dir = "/tmp/kp-fa-\(UUID().uuidString.prefix(8))"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            path = dir + "/r.sock"
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = try RuntimeControl.makeAddress(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
            Thread.detachNewThread { [self] in serve() }
        }

        var received: [RuntimeControl.Request] {
            lock.withLock { requests }
        }

        func answer(with respond: @escaping Respond) {
            lock.withLock { self.respond = respond }
        }

        private func serve() {
            defer { close(fd) }
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }
                if lock.withLock({ stopped }) { return }
                RuntimeControl.setTimeouts(client, seconds: 2)
                guard let line = try? RuntimeControl.readLine(client),
                      let request = try? JSONDecoder().decode(RuntimeControl.Request.self, from: line)
                else { continue }
                let respond = lock.withLock { () -> Respond in
                    requests.append(request)
                    return self.respond
                }
                if var data = try? JSONEncoder().encode(respond(request)) {
                    data.append(0x0A)
                    try? RuntimeControl.writeAll(client, data)
                }
            }
        }

        /// Wakes the serving thread, which then closes the socket itself.
        func stop() {
            let first = lock.withLock { () -> Bool in
                defer { stopped = true }
                return !stopped
            }
            guard first else { return }
            _ = try? RuntimeControl.send(.init(operation: .status), timeout: 1, socketPath: path)
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
    }

    private static func answer(_ operation: RuntimeControl.Operation, ok: Bool = true, layer: String? = nil,
                               layers: [String]? = nil, hrm: RuntimeControl.HrmStatsSummary? = nil,
                               error: String? = nil) -> RuntimeControl.Response
    {
        var response = RuntimeControl.Response(ok: ok, operation: operation, state: .running, workerPID: 42,
                                               failure: nil, lastError: error, layer: layer, appPID: 1,
                                               appVersion: "test")
        response.layers = layers
        response.hrmStats = hrm
        return response
    }

    private var fake: FakeApp?
    private var savedPath = ""
    private var savedAccess = ConfigFacade.EngineAccess.viaApp

    override func setUp() {
        savedPath = ConfigFacade.appControlSocketPath
        savedAccess = ConfigFacade.engineAccess
        ConfigFacade.engineAccess = .viaApp
    }

    override func tearDown() {
        fake?.stop()
        ConfigFacade.appControlSocketPath = savedPath
        ConfigFacade.engineAccess = savedAccess
    }

    private func useFakeApp(_ respond: @escaping @Sendable (RuntimeControl.Request) -> RuntimeControl.Response) throws -> FakeApp {
        let app = try FakeApp(respond: respond)
        fake = app
        ConfigFacade.appControlSocketPath = app.path
        return app
    }

    func testCurrentLayerAndLayerNamesComeFromTheApp() async throws {
        let app = try useFakeApp { request in
            switch request.operation {
            case .layer: Self.answer(.layer, layer: "nav")
            case .layers: Self.answer(.layers, layers: ["base", "nav"])
            default: Self.answer(request.operation, ok: false, error: "unexpected")
            }
        }
        let facade = ConfigFacade()
        let layer = try await facade.tcpGetCurrentLayer()
        let layers = try await facade.tcpGetLayers()
        XCTAssertEqual(layer, "nav")
        XCTAssertEqual(layers, ["base", "nav"])
        XCTAssertEqual(app.received.map(\.operation), [.layer, .layers])
    }

    func testChangeLayerSendsTheNameAndReportsTheAppsAnswer() async throws {
        let app = try useFakeApp { request in
            Self.answer(.changeLayer, ok: request.argument == "nav", error: "no such layer")
        }
        let facade = ConfigFacade()
        let switched = await facade.tcpChangeLayer("nav")
        let refused = await facade.tcpChangeLayer("missing")
        XCTAssertTrue(switched)
        XCTAssertFalse(refused)
        XCTAssertEqual(app.received.map(\.argument), ["nav", "missing"])
    }

    func testReloadIsAskedOfTheAppAndFailsWhenItSaysSo() async throws {
        let app = try useFakeApp { _ in Self.answer(.reload) }
        let reloaded = await ConfigFacade().tcpReload()
        XCTAssertTrue(reloaded)
        XCTAssertEqual(app.received.map(\.operation), [.reload])

        app.answer { _ in Self.answer(.reload, ok: false, error: "config invalid") }
        let failed = await ConfigFacade().tcpReload()
        XCTAssertFalse(failed)
    }

    /// An `ok: false` answer becomes an error carrying the app's own message.
    func testRefusalSurfacesTheAppsMessage() async throws {
        _ = try useFakeApp { _ in Self.answer(.layer, ok: false, error: "The remapping engine did not answer") }
        do {
            _ = try await ConfigFacade().tcpGetCurrentLayer()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("did not answer"), "\(error)")
        }
    }

    /// Health means the engine answered through the app, not just "running".
    func testHealthNeedsAnEngineAnswer() async throws {
        let app = try useFakeApp { _ in Self.answer(.layer, layer: "base") }
        let healthy = await ConfigFacade().tcpCheckHealth()
        XCTAssertTrue(healthy)

        app.answer { _ in Self.answer(.layer, layer: nil) }
        let unhealthy = await ConfigFacade().tcpCheckHealth()
        XCTAssertFalse(unhealthy)
    }

    func testHrmStatsAreRelayed() async throws {
        let app = try useFakeApp { request in
            request.operation == .hrmStats
                ? Self.answer(.hrmStats, hrm: .init(totalDecisions: 9, tapCount: 6, holdCount: 3))
                : Self.answer(request.operation)
        }
        let facade = ConfigFacade()
        let stats = try await facade.tcpGetHrmStats()
        try await facade.tcpResetHrmStats()
        XCTAssertEqual([stats.totalDecisions, stats.tapCount, stats.holdCount], [9, 6, 3])
        XCTAssertEqual(app.received.map(\.operation), [.hrmStats, .resetHrmStats])
    }

    func testNoAppMeansNotAvailable() async {
        ConfigFacade.appControlSocketPath = "/tmp/kp-no-app-\(UUID().uuidString.prefix(8)).sock"
        let healthy = await ConfigFacade().tcpCheckHealth()
        let reloaded = await ConfigFacade().tcpReload()
        XCTAssertFalse(healthy)
        XCTAssertFalse(reloaded)
    }
}

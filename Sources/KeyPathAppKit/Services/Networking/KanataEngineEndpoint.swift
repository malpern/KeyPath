import Foundation
import KeyPathCore
import Network
import os

/// Where a client reaches the engine (ADR-046).
///
/// Production clients use `.session`: the running worker's Unix-domain control
/// socket, which admits only this app. There is no TCP fallback. A fallback
/// would connect to whatever holds the old port, which is exactly the squatter
/// the socket exists to shut out. `.tcp` remains for tests' local mock servers;
/// a lint test keeps it out of `Sources`.
enum KanataEngineEndpoint: Sendable, Equatable, CustomStringConvertible {
    case session
    case tcp(host: String, port: Int)

    /// Looked up at every connect: a restarted worker has a new socket. Nil
    /// when no worker is running.
    func resolve() -> NWEndpoint? {
        switch self {
        case .session:
            EngineControlEndpoint.socketPath.map { NWEndpoint.unix(path: $0) }
        case let .tcp(host, port):
            .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        }
    }

    var description: String {
        switch self {
        case .session: "engine socket \(EngineControlEndpoint.socketPath ?? "(no running worker)")"
        case let .tcp(host, port): "\(host):\(port)"
        }
    }
}

/// The running worker's engine socket path, published by
/// `ServiceLifecycleCoordinator` from the worker's own report and cleared when
/// the worker stops. Readable from any thread.
enum EngineControlEndpoint {
    private static let path = OSAllocatedUnfairLock<String?>(initialState: nil)

    static var socketPath: String? {
        path.withLock { $0 }
    }

    static func publish(_ socketPath: String?) {
        let changed = path.withLock { current -> Bool in
            defer { current = socketPath }
            return current != socketPath
        }
        if changed {
            AppLogger.shared.info("🔌 [Engine] Control socket: \(socketPath ?? "none")")
        }
    }
}

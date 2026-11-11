import Foundation
import KeyPathCore
import Network

/// ServerResponse matches the Rust protocol ServerResponse enum
/// Format: {"status":"Ok"} or {"status":"Error","msg":"..."}
struct TcpServerResponse: Codable, Sendable {
    let status: String
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case status
        case msg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        msg = try container.decodeIfPresent(String.self, forKey: .msg)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(msg, forKey: .msg)
    }

    var isOk: Bool {
        status == "Ok"
    }

    var isError: Bool {
        status == "Error"
    }
}

/// Simple completion flag for thread-safe continuation handling
final class CompletionFlag: @unchecked Sendable {
    private var completed = false
    private let lock = NSLock()

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

/// Client for the engine's JSON control protocol.
///
/// Design principles:
/// - Local IPC, not distributed networking
/// - Persistent connection for reliability
/// - Simple timeout mechanism
/// - Connection pooling for efficiency
///
/// **Security (ADR-046):** production clients reach the engine only through
/// the running worker's Unix-domain socket, which admits only this app (uid,
/// PID and PID version). The worker opens no TCP port. The type keeps its
/// name; the protocol is the same JSON it always spoke.
actor KanataTCPClient {
    nonisolated let endpoint: KanataEngineEndpoint
    let timeout: TimeInterval
    let retryBackoffSeconds: TimeInterval = 0.5

    // Connection management
    var connection: NWConnection?
    var isConnecting = false
    /// Waiters for an in-flight connection attempt. Callers that arrive while isConnecting
    /// is true register here and are resumed when the connection completes or fails.
    var connectionWaiters: [CheckedContinuation<NWConnection, any Error>] = []

    // MARK: - Read Buffer (Critical for Two-Line Protocol)

    //
    // **WHY THIS EXISTS:**
    // Kanata's TCP protocol sends TWO lines for Hello/Validate/Reload commands:
    //   Line 1: {"status":"Ok"}\n
    //   Line 2: {"HelloOk":...}\n or {"ValidationResult":...}\n or {"ReloadResult":...}\n
    //
    // These lines can arrive in a single TCP packet. Without buffering, the first
    // readUntilNewline() call would consume BOTH lines, then the second read would
    // hang forever waiting for data that was already discarded.
    //
    // **HOW IT WORKS:**
    // - readUntilNewline() always returns exactly ONE line (up to \n)
    // - Leftover data stays in readBuffer for subsequent calls
    // - Buffer is cleared when connection closes
    //
    // **TEST:** If you modify this, verify with: KEYPATH_ENABLE_TCP_TESTS=1 swift test
    // and manually test saving a key mapping (2→3) in the UI.
    var readBuffer = Data()

    /// Handshake cache
    var cachedHello: TcpHelloOk?

    /// Request ID management for reliable response correlation
    var nextRequestId: UInt64 = 1

    /// Serialize send/receive cycles on the shared TCP connection.
    /// NWConnection receive callbacks are not safe to overlap for request/response RPC.
    var isSending = false
    struct SendWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    var sendWaiters: [SendWaiter] = []

    /// Generate next request ID (monotonically increasing)
    func generateRequestId() -> UInt64 {
        let id = nextRequestId
        nextRequestId += 1
        return id
    }

    // MARK: - Initialization

    /// Default timeout: 5 seconds for production, 0.1 seconds for tests
    private static var defaultTimeout: TimeInterval {
        TestEnvironment.isRunningTests ? 0.1 : 5.0
    }

    /// A client of the running worker's engine socket (ADR-046).
    init(timeout: TimeInterval? = nil) {
        endpoint = .session
        self.timeout = timeout ?? Self.defaultTimeout
    }

    /// A client of a TCP server: tests' mock servers only. Production code
    /// must use `init(timeout:)`; `EngineTransportLintTests` enforces it.
    init(
        host: String = "127.0.0.1", port: Int, timeout: TimeInterval? = nil,
        reuseConnection _: Bool = true
    ) {
        endpoint = .tcp(host: host, port: port)
        self.timeout = timeout ?? Self.defaultTimeout
    }

    /// Cache-friendly hello payload strips transient request correlation fields.
    nonisolated func cachedHelloPayload(from hello: TcpHelloOk) -> TcpHelloOk {
        TcpHelloOk(
            version: hello.version,
            protocolVersion: hello.protocolVersion,
            capabilities: hello.capabilities,
            request_id: nil
        )
    }
}

// MARK: - Result Types

enum TCPReloadResult: Sendable {
    case success(response: String)
    case failure(error: String, response: String)
    case networkError(String)

    var isSuccess: Bool {
        switch self {
        case .success:
            true
        default:
            false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .failure(error, _):
            error
        case let .networkError(error):
            error
        case .success:
            nil
        }
    }

    var response: String? {
        switch self {
        case let .success(response):
            response
        case let .failure(_, response):
            response
        case .networkError:
            nil
        }
    }

    var isCancellation: Bool {
        guard let message = errorMessage else { return false }
        return message.contains("CancellationError") || message.localizedCaseInsensitiveContains("cancel")
    }
}

import Foundation
import KeyPathCore
import Network

// MARK: - KeyPath Action URI

/// Represents a parsed `keypath://` URI from push-msg
/// Format: `keypath://[action]/[target][/subpath...][?query=params]`
///
/// Examples:
/// - `keypath://launch/obsidian`
/// - `keypath://layer/nav`
/// - `keypath://rule/caps-to-escape/fired`
/// - `keypath://notify?title=Saved&sound=pop`
public struct KeyPathActionURI: Sendable, Equatable {
    /// The URL scheme (always "keypath")
    public static let scheme = "keypath"

    /// The action type (e.g., "launch", "layer", "rule", "notify")
    public let action: String

    /// Path components after the action (e.g., ["obsidian"] or ["nav", "activate"])
    public let pathComponents: [String]

    /// Query parameters (e.g., ["title": "Saved", "sound": "pop"])
    public let queryItems: [String: String]

    /// The original URL
    public let url: URL

    /// First path component (convenience accessor)
    public var target: String? { pathComponents.first }

    /// Parse a keypath:// URI string
    /// Returns nil if the string is not a valid keypath:// URI
    public init?(string: String) {
        guard let url = URL(string: string),
              url.scheme == Self.scheme,
              let host = url.host, !host.isEmpty
        else {
            return nil
        }

        self.url = url
        action = host

        // Parse path components (remove empty strings from leading/trailing slashes)
        pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // Parse query items
        var items: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                items[item.name] = item.value ?? ""
            }
        }
        queryItems = items
    }

    /// Check if a string is a keypath:// URI
    public static func isKeyPathURI(_ string: String) -> Bool {
        string.hasPrefix("\(scheme)://")
    }
}

// MARK: - Event Types

/// Event types emitted by Kanata's TCP server
public enum KanataEvent: Sendable {
    /// Layer changed to a new layer name
    case layerChange(String)
    /// KeyPath action URI received via push-msg
    case actionURI(KeyPathActionURI)
    /// Raw message received (non-keypath:// format)
    case rawMessage(String)
}

/// Monitors Kanata's TCP server for events.
/// Handles `LayerChange`, `CurrentLayerName`, and `MessagePush` messages.
actor KanataEventListener {
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var port: Int?
    private var layerHandler: (@Sendable (String) async -> Void)?
    private var actionURIHandler: (@Sendable (KeyPathActionURI) async -> Void)?
    private var unknownMessageHandler: (@Sendable (String) async -> Void)?
    private let listenerQueue = DispatchQueue(label: "com.keypath.event-listener")

    /// Start listening for Kanata events
    /// - Parameters:
    ///   - port: TCP port where Kanata server is running
    ///   - onLayerChange: Called when layer changes (LayerChange or CurrentLayerName)
    ///   - onActionURI: Called when a `keypath://` URI is received via push-msg
    ///   - onUnknownMessage: Called for non-keypath:// messages (for debugging/errors)
    func start(
        port: Int,
        onLayerChange: @escaping @Sendable (String) async -> Void,
        onActionURI: (@Sendable (KeyPathActionURI) async -> Void)? = nil,
        onUnknownMessage: (@Sendable (String) async -> Void)? = nil
    ) async {
        if self.port == port, listenTask != nil { return }
        await stop()
        self.port = port
        // Set handlers AFTER stop() to avoid them being cleared
        layerHandler = onLayerChange
        actionURIHandler = onActionURI
        unknownMessageHandler = onUnknownMessage
        AppLogger.shared.log("🌐 [EventListener] Starting event listener on port \(port)")
        listenTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await listenLoop()
        }
    }

    func stop() async {
        AppLogger.shared.log("🌐 [EventListener] Stopping event listener")
        listenTask?.cancel()
        listenTask = nil
        pollTask?.cancel()
        pollTask = nil
        port = nil
        layerHandler = nil
        actionURIHandler = nil
        unknownMessageHandler = nil
    }

    private func listenLoop() async {
        guard let port else { return }
        while !Task.isCancelled {
            do {
                try await connectAndStream(port: port)
            } catch {
                AppLogger.shared.debug("🌐 [EventListener] stream ended: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func connectAndStream(port: Int) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        try await waitForReady(connection)
        AppLogger.shared.log("🌐 [EventListener] Connected to kanata TCP server")

        AppLogger.shared.log("🌐 [EventListener] Sending Hello message")
        try await send(jsonObject: ["Hello": [:] as [String: String]], over: connection)

        AppLogger.shared.log("🌐 [EventListener] Sending RequestCurrentLayerName message")
        try await send(
            jsonObject: ["RequestCurrentLayerName": [:] as [String: String]], over: connection
        )

        pollTask?.cancel()
        pollTask = Task(priority: .background) { [weak self, weak connection] in
            guard let self, let connection else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                try? await send(
                    jsonObject: ["RequestCurrentLayerName": [:] as [String: String]], over: connection
                )
            }
        }

        var buffer = Data()

        while !Task.isCancelled {
            guard let chunk = try await receiveChunk(on: connection) else {
                throw ListenerError.connectionClosed
            }
            if chunk.isEmpty { continue }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var lineData = buffer.subdata(in: 0 ..< newlineIndex)
                if let last = lineData.last, last == 0x0D {
                    lineData.removeLast()
                }
                buffer.removeSubrange(0 ... newlineIndex)
                guard !lineData.isEmpty else { continue }
                if let line = String(data: lineData, encoding: .utf8) {
                    await handleLine(line)
                }
            }
        }

        connection.cancel()
        pollTask?.cancel()
        pollTask = nil
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.stateUpdateHandler = nil
                    continuation.resume()
                case let .failed(error):
                    connection?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    connection?.stateUpdateHandler = nil
                    continuation.resume(throwing: ListenerError.connectionClosed)
                default:
                    break
                }
            }
            connection.start(queue: listenerQueue)
        }
    }

    private func send(jsonObject: Any, over connection: NWConnection) async throws {
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        var payload = data
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: payload,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func receiveChunk(on connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let content {
                    continuation.resume(returning: content)
                    return
                }
                if isComplete {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    private func handleLine(_ line: String) async {
        // Reduce log noise - log heartbeat messages at debug level
        AppLogger.shared.debug("🌐 [EventListener] Received line: '\(line)'")

        guard let data = line.data(using: .utf8) else {
            AppLogger.shared.log("🌐 [EventListener] Failed to convert line to UTF8 data")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.shared.log("🌐 [EventListener] Failed to parse JSON from: '\(line)'")
            return
        }

        AppLogger.shared.debug("🌐 [EventListener] Parsed JSON keys: \(json.keys.joined(separator: ", "))")

        // Handle LayerChange events
        if let layer = json["LayerChange"] as? [String: Any], let new = layer["new"] as? String {
            AppLogger.shared.log("🌐 [EventListener] Layer change -> \(new)")
            if let handler = layerHandler {
                await handler(new)
            }
            return
        }

        // Handle CurrentLayerName events (response to polling)
        if let current = json["CurrentLayerName"] as? [String: Any],
           let name = current["name"] as? String {
            AppLogger.shared.debug("🌐 [EventListener] Current layer -> \(name)")
            if let handler = layerHandler {
                await handler(name)
            }
            return
        }

        // Handle MessagePush events (keypath:// URIs via push-msg)
        // Format from Kanata: {"MessagePush":{"message":["keypath://launch/obsidian"]}}
        if let push = json["MessagePush"] as? [String: Any],
           let messages = push["message"] as? [Any] {
            AppLogger.shared.log("🌐 [EventListener] MessagePush received: \(messages)")

            for item in messages {
                guard let messageString = item as? String else { continue }

                // Try to parse as keypath:// URI
                if let actionURI = KeyPathActionURI(string: messageString) {
                    AppLogger.shared.log(
                        "🎯 [EventListener] Action URI: \(actionURI.action)/\(actionURI.pathComponents.joined(separator: "/"))"
                    )
                    if let handler = actionURIHandler {
                        await handler(actionURI)
                    }
                } else {
                    // Not a keypath:// URI - report as unknown
                    AppLogger.shared.log("⚠️ [EventListener] Unknown message format: \(messageString)")
                    if let handler = unknownMessageHandler {
                        await handler(messageString)
                    }
                }
            }
            return
        }

        AppLogger.shared.debug("🌐 [EventListener] Unhandled message type")
    }

    enum ListenerError: Error {
        case connectionClosed
    }
}

// MARK: - Backward Compatibility

/// Deprecated: Use KanataEventListener instead
@available(*, deprecated, renamed: "KanataEventListener")
typealias LayerChangeListener = KanataEventListener

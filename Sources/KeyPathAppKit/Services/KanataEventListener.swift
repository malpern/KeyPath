import Foundation
import KeyPathCore
import Network

// MARK: - KeyPath Action URI

/// Represents a parsed action URI from push-msg
///
/// Supports two equivalent syntaxes:
/// 1. **Full URI** (for deep links): `keypath://[action]/[target][/subpath...][?query=params]`
/// 2. **Shorthand** (for Kanata configs): `[action]:[target][:[subpath]][?query=params]`
///
/// Examples (Full URI):
/// - `keypath://launch/Obsidian`
/// - `keypath://layer/nav/activate`
/// - `keypath://notify?title=Saved&sound=pop`
///
/// Examples (Shorthand - lowercase resolves to Title Case):
/// - `launch:obsidian` → launches "Obsidian"
/// - `layer:nav:activate` → layer "nav", subpath "activate"
/// - `notify:?title=Saved` → notification with title
public struct KeyPathActionURI: Sendable, Equatable {
    /// The URL scheme (always "keypath")
    public static let scheme = "keypath"

    /// The action type (e.g., "launch", "layer", "rule", "notify")
    public let action: String

    /// Path components after the action (e.g., ["obsidian"] or ["nav", "activate"])
    public let pathComponents: [String]

    /// Query parameters (e.g., ["title": "Saved", "sound": "pop"])
    public let queryItems: [String: String]

    /// The original URL (synthesized for shorthand syntax)
    public let url: URL

    /// Whether this was parsed from shorthand syntax
    public let isShorthand: Bool

    /// First path component (convenience accessor)
    public var target: String? { pathComponents.first }

    /// First path component converted to Title Case (for display)
    /// e.g., "obsidian" → "Obsidian", "visual studio code" → "Visual Studio Code"
    public var targetTitleCase: String? {
        guard let target else { return nil }
        return target.titleCased
    }

    /// Parse a keypath:// URI or shorthand colon-syntax string
    /// Returns nil if the string is not a valid action URI
    public init?(string: String) {
        // Try full URI first
        if Self.isKeyPathURI(string) {
            guard let parsed = Self.parseFullURI(string) else { return nil }
            self = parsed
        }
        // Try shorthand colon syntax
        else if Self.isShorthandSyntax(string) {
            guard let parsed = Self.parseShorthand(string) else { return nil }
            self = parsed
        }
        // Not a valid format
        else {
            return nil
        }
    }

    /// Internal initializer for building from parsed components
    private init(
        action: String,
        pathComponents: [String],
        queryItems: [String: String],
        url: URL,
        isShorthand: Bool
    ) {
        self.action = action
        self.pathComponents = pathComponents
        self.queryItems = queryItems
        self.url = url
        self.isShorthand = isShorthand
    }

    // MARK: - Full URI Parsing

    /// Check if a string is a keypath:// URI
    public static func isKeyPathURI(_ string: String) -> Bool {
        string.hasPrefix("\(scheme)://")
    }

    /// Parse full URI format: keypath://action/target/subpath?query
    private static func parseFullURI(_ string: String) -> KeyPathActionURI? {
        guard let url = URL(string: string),
              url.scheme == scheme,
              let host = url.host, !host.isEmpty
        else {
            return nil
        }

        let action = host

        // Parse path components (remove empty strings from leading/trailing slashes)
        let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // Parse query items
        var items: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                items[item.name] = item.value ?? ""
            }
        }

        return KeyPathActionURI(
            action: action,
            pathComponents: pathComponents,
            queryItems: items,
            url: url,
            isShorthand: false
        )
    }

    // MARK: - Shorthand Syntax Parsing

    /// Check if a string is shorthand colon syntax (e.g., "launch:obsidian")
    /// Must have at least one colon and not be a URL scheme
    public static func isShorthandSyntax(_ string: String) -> Bool {
        // Must contain a colon
        guard string.contains(":") else { return false }
        // Must not be a URL scheme (no "://")
        guard !string.contains("://") else { return false }
        // First part (action) must not be empty
        guard let colonIndex = string.firstIndex(of: ":"),
              colonIndex != string.startIndex
        else { return false }
        return true
    }

    /// Parse shorthand format: action:target:subpath?query
    /// - `launch:obsidian` → action="launch", path=["obsidian"]
    /// - `layer:nav:activate` → action="layer", path=["nav", "activate"]
    /// - `notify:?title=Hello` → action="notify", path=[], query=["title": "Hello"]
    private static func parseShorthand(_ string: String) -> KeyPathActionURI? {
        // Split query params first
        let parts = string.split(separator: "?", maxSplits: 1)
        let mainPart = String(parts[0])
        let queryString = parts.count > 1 ? String(parts[1]) : nil

        // Split by colons
        let colonParts = mainPart.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard !colonParts.isEmpty else { return nil }

        let action = colonParts[0]
        guard !action.isEmpty else { return nil }

        // Remaining parts are path components (filter out empty from trailing colons)
        let pathComponents = Array(colonParts.dropFirst()).filter { !$0.isEmpty }

        // Parse query string
        var queryItems: [String: String] = [:]
        if let queryString {
            // Use URLComponents to parse query string
            var components = URLComponents()
            components.query = queryString
            if let items = components.queryItems {
                for item in items {
                    queryItems[item.name] = item.value ?? ""
                }
            }
        }

        // Synthesize a full URL for compatibility
        var urlString = "\(scheme)://\(action)"
        if !pathComponents.isEmpty {
            urlString += "/" + pathComponents.joined(separator: "/")
        }
        if let queryString {
            urlString += "?" + queryString
        }

        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
            ?? URL(string: urlString)
        else {
            // Fallback: create a basic URL
            guard let fallbackURL = URL(string: "\(scheme)://\(action)") else { return nil }
            return KeyPathActionURI(
                action: action,
                pathComponents: pathComponents,
                queryItems: queryItems,
                url: fallbackURL,
                isShorthand: true
            )
        }

        return KeyPathActionURI(
            action: action,
            pathComponents: pathComponents,
            queryItems: queryItems,
            url: url,
            isShorthand: true
        )
    }
}

// MARK: - String Extensions

extension String {
    /// Convert string to Title Case
    /// "obsidian" → "Obsidian"
    /// "visual studio code" → "Visual Studio Code"
    var titleCased: String {
        split(separator: " ")
            .map { word in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
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
    /// Key input event (physical key press/release)
    case keyInput(key: String, action: KanataKeyAction, timestamp: UInt64)
}

/// Key action from Kanata TCP KeyInput events
/// Note: Kanata uses serde(rename_all = "lowercase") so actions are lowercase in JSON
public enum KanataKeyAction: String, Sendable {
    case press
    case release
    case `repeat`
}

/// Hold activation info from Kanata TCP HoldActivated events
/// Sent when a tap-hold key transitions to hold state after the hold threshold
public struct KanataHoldActivation: Sendable {
    /// Physical key name (e.g., "caps")
    public let key: String
    /// Hold action description (e.g., "lctl+lmet+lalt+lsft")
    public let action: String
    /// Timestamp in milliseconds since Kanata start
    public let timestamp: UInt64
}

/// Tap activation info from Kanata TCP TapActivated events
/// Sent when a tap-hold key triggers its tap action
public struct KanataTapActivation: Sendable {
    /// Physical key name (e.g., "caps")
    public let key: String
    /// Tap action output (e.g., "esc")
    public let action: String
    /// Timestamp in milliseconds since Kanata start
    public let timestamp: UInt64
}

/// Monitors Kanata's TCP server for events.
/// Handles `LayerChange`, `CurrentLayerName`, `MessagePush`, and `KeyInput` messages.
actor KanataEventListener {
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var port: Int?
    private var layerHandler: (@Sendable (String) async -> Void)?
    private var actionURIHandler: (@Sendable (KeyPathActionURI) async -> Void)?
    private var unknownMessageHandler: (@Sendable (String) async -> Void)?
    private var keyInputHandler: (@Sendable (String, KanataKeyAction) async -> Void)?
    private var holdActivatedHandler: (@Sendable (KanataHoldActivation) async -> Void)?
    private var tapActivatedHandler: (@Sendable (KanataTapActivation) async -> Void)?
    /// Capabilities advertised by Kanata in HelloOk (e.g., "hold_activated", "tap_activated").
    private var capabilities: Set<String> = []
    private let listenerQueue = DispatchQueue(label: "com.keypath.event-listener")

    /// Start listening for Kanata events
    /// - Parameters:
    ///   - port: TCP port where Kanata server is running
    ///   - onLayerChange: Called when layer changes (LayerChange or CurrentLayerName)
    ///   - onActionURI: Called when a `keypath://` URI is received via push-msg
    ///   - onUnknownMessage: Called for non-keypath:// messages (for debugging/errors)
    ///   - onKeyInput: Called when a physical key is pressed/released (from Kanata's KeyInput events)
    ///   - onHoldActivated: Called when a tap-hold key transitions to hold state
    ///   - onTapActivated: Called when a tap-hold key triggers its tap action
    func start(
        port: Int,
        onLayerChange: @escaping @Sendable (String) async -> Void,
        onActionURI: (@Sendable (KeyPathActionURI) async -> Void)? = nil,
        onUnknownMessage: (@Sendable (String) async -> Void)? = nil,
        onKeyInput: (@Sendable (String, KanataKeyAction) async -> Void)? = nil,
        onHoldActivated: (@Sendable (KanataHoldActivation) async -> Void)? = nil,
        onTapActivated: (@Sendable (KanataTapActivation) async -> Void)? = nil
    ) async {
        if self.port == port, listenTask != nil { return }
        await stop()
        self.port = port
        // Set handlers AFTER stop() to avoid them being cleared
        layerHandler = onLayerChange
        actionURIHandler = onActionURI
        unknownMessageHandler = onUnknownMessage
        keyInputHandler = onKeyInput
        holdActivatedHandler = onHoldActivated
        tapActivatedHandler = onTapActivated
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
        keyInputHandler = nil
        holdActivatedHandler = nil
        tapActivatedHandler = nil
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

        // Handle KeyInput events (physical key press/release from Kanata)
        // Format from Kanata: {"KeyInput":{"key":"h","action":"press","t":12345}}
        if let keyInput = json["KeyInput"] as? [String: Any],
           let key = keyInput["key"] as? String,
           let actionStr = keyInput["action"] as? String {
            if let action = KanataKeyAction(rawValue: actionStr) {
                AppLogger.shared.info("⌨️ [EventListener] KeyInput: \(key) \(action)")
                if let handler = keyInputHandler {
                    await handler(key, action)
                }
            }
            return
        }

        // Handle HelloOk (capability advertisement)
        if let helloOk = json["HelloOk"] as? [String: Any] {
            let caps = (helloOk["capabilities"] as? [String]) ?? []
            capabilities = Set(caps.map { $0.lowercased() })
            AppLogger.shared.log(
                "🌐 [EventListener] HelloOk caps=\(caps.joined(separator: ",")) protocol=\(helloOk["protocol"] ?? "?")"
            )
            return
        }

        // Handle HoldActivated events (tap-hold key transitioned to hold state)
        // Format from Kanata: {"HoldActivated":{"key":"caps","action":"lctl+lmet+lalt+lsft","t":12345}}
        if let holdActivated = json["HoldActivated"] as? [String: Any],
           let key = holdActivated["key"] as? String,
           let action = holdActivated["action"] as? String,
           let timestamp = holdActivated["t"] as? UInt64 {
            // Respect capability advertisement when available; still process for backward compat
            if capabilities.isEmpty || capabilities.contains("hold_activated") {
                AppLogger.shared.log("🔒 [EventListener] HoldActivated: \(key) -> \(action)")
                let activation = KanataHoldActivation(key: key, action: action, timestamp: timestamp)
                if let handler = holdActivatedHandler {
                    await handler(activation)
                }
            } else {
                AppLogger.shared.debug("🔒 [EventListener] HoldActivated ignored (capability not advertised)")
            }
            return
        }

        // Handle TapActivated events (tap-hold key triggered its tap action)
        // Format from Kanata: {"TapActivated":{"key":"caps","action":"esc","t":12345}}
        if let tapActivated = json["TapActivated"] as? [String: Any],
           let key = tapActivated["key"] as? String,
           let action = tapActivated["action"] as? String,
           let timestamp = tapActivated["t"] as? UInt64 {
            // Respect capability advertisement when available; still process for backward compat
            if capabilities.isEmpty || capabilities.contains("tap_activated") {
                AppLogger.shared.log("👆 [EventListener] TapActivated: \(key) -> \(action)")
                let activation = KanataTapActivation(key: key, action: action, timestamp: timestamp)
                if let handler = tapActivatedHandler {
                    await handler(activation)
                }
            } else {
                AppLogger.shared.debug("👆 [EventListener] TapActivated ignored (capability not advertised)")
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

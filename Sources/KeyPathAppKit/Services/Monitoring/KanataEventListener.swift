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
    public var target: String? {
        pathComponents.first
    }

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
           let queryItems = components.queryItems
        {
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
    /// Listener session that observed the activation
    public let sessionID: Int
    /// Wall-clock observation time in KeyPath
    public let observedAt: Date
    /// Why this key resolved as hold (kebab-case, e.g. "opposite-hand", "timeout")
    public let reason: String?
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
    /// Listener session that observed the activation
    public let sessionID: Int
    /// Wall-clock observation time in KeyPath
    public let observedAt: Date
    /// Why this key resolved as tap (kebab-case, e.g. "prior-idle", "release-before-timeout")
    public let reason: String?
}

/// One-shot activation info from Kanata TCP OneShotActivated events
/// Sent when a one-shot modifier key is activated
public struct KanataOneShotActivation: Sendable {
    /// Physical key name (e.g., "lsft")
    public let key: String
    /// Modifier(s) being applied (e.g., "lsft" or "lctl+lsft")
    public let modifiers: String
    /// Timestamp in milliseconds since Kanata start
    public let timestamp: UInt64
    /// Listener session that observed the activation
    public let sessionID: Int
    /// Wall-clock observation time in KeyPath
    public let observedAt: Date
}

/// Chord resolution info from Kanata TCP ChordResolved events
/// Sent when a chord (multi-key combo) resolves to an action
public struct KanataChordResolution: Sendable {
    /// Chord keys pressed (e.g., "s+d")
    public let keys: String
    /// Resolved action description
    public let action: String
    /// Timestamp in milliseconds since Kanata start
    public let timestamp: UInt64
    /// Listener session that observed the resolution
    public let sessionID: Int
    /// Wall-clock observation time in KeyPath
    public let observedAt: Date
}

/// Tap-dance resolution info from Kanata TCP TapDanceResolved events
/// Sent when a tap-dance resolves to a specific action
public struct KanataTapDanceResolution: Sendable {
    /// Physical key name (e.g., "q")
    public let key: String
    /// Number of taps detected
    public let tapCount: UInt8
    /// Resolved action description
    public let action: String
    /// Timestamp in milliseconds since Kanata start
    public let timestamp: UInt64
    /// Listener session that observed the resolution
    public let sessionID: Int
    /// Wall-clock observation time in KeyPath
    public let observedAt: Date
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
    private var keyInputHandler: (@Sendable (KanataObservedKeyInput) async -> Void)?
    private var holdActivatedHandler: (@Sendable (KanataHoldActivation) async -> Void)?
    private var tapActivatedHandler: (@Sendable (KanataTapActivation) async -> Void)?
    private var oneShotActivatedHandler: (@Sendable (KanataOneShotActivation) async -> Void)?
    private var chordResolvedHandler: (@Sendable (KanataChordResolution) async -> Void)?
    private var tapDanceResolvedHandler: (@Sendable (KanataTapDanceResolution) async -> Void)?
    private var hrmTraceHandler: (@Sendable (KanataHrmTraceEvent) async -> Void)?
    private var capabilitiesUpdatedHandler: (@Sendable ([String]) async -> Void)?
    /// Capabilities advertised by Kanata in HelloOk (normalized to dash-case, e.g. "hold-activated").
    private var capabilities: Set<String> = []
    private var activeConnection: NWConnection?
    private var sessionCounter = 0
    private var currentSessionID: Int?
    private var isHrmTraceSubscribed = false
    private var isAwaitingHrmTraceSubscribeAck = false
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
    ///   - onOneShotActivated: Called when a one-shot modifier key is activated
    ///   - onChordResolved: Called when a chord (multi-key combo) resolves
    ///   - onTapDanceResolved: Called when a tap-dance resolves to an action
    ///   - onHrmTrace: Called when an HRM trace decision event is received
    ///   - onCapabilitiesUpdated: Called when HelloOk capabilities are received
    func start(
        port: Int,
        onLayerChange: @escaping @Sendable (String) async -> Void,
        onActionURI: (@Sendable (KeyPathActionURI) async -> Void)? = nil,
        onUnknownMessage: (@Sendable (String) async -> Void)? = nil,
        onKeyInput: (@Sendable (KanataObservedKeyInput) async -> Void)? = nil,
        onHoldActivated: (@Sendable (KanataHoldActivation) async -> Void)? = nil,
        onTapActivated: (@Sendable (KanataTapActivation) async -> Void)? = nil,
        onOneShotActivated: (@Sendable (KanataOneShotActivation) async -> Void)? = nil,
        onChordResolved: (@Sendable (KanataChordResolution) async -> Void)? = nil,
        onTapDanceResolved: (@Sendable (KanataTapDanceResolution) async -> Void)? = nil,
        onHrmTrace: (@Sendable (KanataHrmTraceEvent) async -> Void)? = nil,
        onCapabilitiesUpdated: (@Sendable ([String]) async -> Void)? = nil
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
        oneShotActivatedHandler = onOneShotActivated
        chordResolvedHandler = onChordResolved
        tapDanceResolvedHandler = onTapDanceResolved
        hrmTraceHandler = onHrmTrace
        capabilitiesUpdatedHandler = onCapabilitiesUpdated
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
        oneShotActivatedHandler = nil
        chordResolvedHandler = nil
        tapDanceResolvedHandler = nil
        hrmTraceHandler = nil
        capabilitiesUpdatedHandler = nil
        capabilities.removeAll()
        isHrmTraceSubscribed = false
        isAwaitingHrmTraceSubscribeAck = false
        activeConnection = nil
        currentSessionID = nil
    }

    private func listenLoop() async {
        guard let port else { return }
        while !Task.isCancelled {
            do {
                try await connectAndStream(port: port)
            } catch {
                AppLogger.shared.log("🌐 [EventListener] Stream ended: \(error.localizedDescription), reconnecting in 1s...")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func connectAndStream(port: Int) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        // Bug 1 fix: ensure cleanup on both normal and error exits
        sessionCounter += 1
        let sessionID = sessionCounter
        currentSessionID = sessionID
        defer {
            connection.cancel()
            pollTask?.cancel()
            pollTask = nil
            activeConnection = nil
            currentSessionID = nil
            isHrmTraceSubscribed = false
            isAwaitingHrmTraceSubscribeAck = false
        }

        try await waitForReady(connection)
        activeConnection = connection
        capabilities.removeAll()
        isHrmTraceSubscribed = false
        isAwaitingHrmTraceSubscribeAck = false
        AppLogger.shared.log("🌐 [EventListener] Connected to kanata TCP server")

        // Bug 2 fix: monitor for post-handshake connection failures.
        // waitForReady() nils out stateUpdateHandler after .ready, so we install a new one
        // that cancels the connection on failure, causing receiveChunk to throw.
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .failed, .cancelled, .waiting:
                AppLogger.shared.log("🌐 [EventListener] Connection state → \(state), cancelling")
                connection?.cancel()
            default:
                break
            }
        }

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
                try? await Task.sleep(for: .milliseconds(500))
                // Bug 3 fix: propagate send errors instead of silently swallowing them.
                // On a dead connection, send() throws — cancel the connection to trigger reconnect.
                do {
                    try await send(
                        jsonObject: ["RequestCurrentLayerName": [:] as [String: String]],
                        over: connection
                    )
                } catch {
                    AppLogger.shared.log("🌐 [EventListener] Poll send failed: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }
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
                    await handleLine(line, sessionID: sessionID)
                }
            }
        }
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
                case let .waiting(error):
                    // Server not reachable (e.g. Kanata restarting). Fail fast so
                    // listenLoop can retry after a delay instead of hanging forever.
                    connection?.stateUpdateHandler = nil
                    connection?.cancel()
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

    private func handleLine(_ line: String, sessionID: Int) async {
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
           let name = current["name"] as? String
        {
            AppLogger.shared.debug("🌐 [EventListener] Current layer -> \(name)")
            if let handler = layerHandler {
                await handler(name)
            }
            return
        }

        // Handle MessagePush events (keypath:// URIs via push-msg)
        // Current upstream format: {"MessagePush":{"message":"layer:nav"}}
        // Back-compat formats: {"MessagePush":{"message":[...]}} or {"MessagePush":{"msg":"..."}}
        if let push = json["MessagePush"] as? [String: Any],
           let messages = Self.extractMessagePushMessages(from: push)
        {
            AppLogger.shared.log("🌐 [EventListener] MessagePush received: \(messages)")

            for messageString in messages {
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
        // Format from Kanata: {"KeyInput":{"key":"h","action":"Press","t":12345}}
        // Note: Kanata sends capitalized action names (Press/Release/Repeat)
        if let keyInput = json["KeyInput"] as? [String: Any],
           let key = keyInput["key"] as? String,
           let actionStr = keyInput["action"] as? String
        {
            // Lowercase the action to match our enum (Kanata sends "Press", we expect "press")
            if let action = KanataKeyAction(rawValue: actionStr.lowercased()) {
                let observed = KanataObservedKeyInput(
                    key: key,
                    action: action,
                    kanataTimestamp: keyInput["t"] as? UInt64,
                    sessionID: sessionID,
                    observedAt: Date()
                )
                AppLogger.shared.debug("⌨️ [EventListener] KeyInput: \(key) \(action)")
                if let handler = keyInputHandler {
                    await handler(observed)
                }
            }
            return
        }

        // Handle HelloOk (capability advertisement)
        if let helloOk = json["HelloOk"] as? [String: Any] {
            let rawCaps = (helloOk["capabilities"] as? [String]) ?? []
            let normalizedCaps = Self.normalizedCapabilities(rawCaps)
            capabilities = Set(normalizedCaps)
            AppLogger.shared.log(
                "🌐 [EventListener] HelloOk caps=\(normalizedCaps.joined(separator: ",")) protocol=\(helloOk["protocol"] ?? "?")"
            )
            if let handler = capabilitiesUpdatedHandler {
                await handler(normalizedCaps)
            }
            await subscribeToHrmTraceIfSupported()
            return
        }

        // Handle HoldActivated events (tap-hold key transitioned to hold state)
        // Format from Kanata: {"HoldActivated":{"key":"caps"}}
        // Note: upstream only sends "key"; "action" and "t" are not included
        if let holdActivated = json["HoldActivated"] as? [String: Any] {
            let key = holdActivated["key"] as? String ?? ""
            let action = holdActivated["action"] as? String ?? ""
            let timestamp = holdActivated["t"] as? UInt64 ?? 0
            let reason = holdActivated["reason"] as? String
            let observedAt = Date()

            // Respect capability advertisement when available; still process for backward compat
            if capabilities.isEmpty || capabilities.contains("hold-activated") {
                AppLogger.shared.log("🔒 [EventListener] HoldActivated: \(key) -> \(action) reason=\(reason ?? "none")")
                let activation = KanataHoldActivation(
                    key: key,
                    action: action,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    observedAt: observedAt,
                    reason: reason
                )
                if let handler = holdActivatedHandler {
                    await handler(activation)
                }
            } else {
                AppLogger.shared.debug("🔒 [EventListener] HoldActivated ignored (capability not advertised)")
            }
            return
        }

        // Handle TapActivated events (tap-hold key triggered its tap action)
        // Format from Kanata: {"TapActivated":{"key":"caps"}}
        // Note: upstream only sends "key"; "action" and "t" are not included
        if let tapActivated = json["TapActivated"] as? [String: Any] {
            let key = tapActivated["key"] as? String ?? ""
            let action = tapActivated["action"] as? String ?? ""
            let timestamp = tapActivated["t"] as? UInt64 ?? 0
            let reason = tapActivated["reason"] as? String
            let observedAt = Date()

            // Respect capability advertisement when available; still process for backward compat
            if capabilities.isEmpty || capabilities.contains("tap-activated") {
                AppLogger.shared.debug("👆 [EventListener] TapActivated: \(key) -> \(action) reason=\(reason ?? "none")")
                let activation = KanataTapActivation(
                    key: key,
                    action: action,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    observedAt: observedAt,
                    reason: reason
                )
                if let handler = tapActivatedHandler {
                    await handler(activation)
                }
            } else {
                AppLogger.shared.debug("👆 [EventListener] TapActivated ignored (capability not advertised)")
            }
            return
        }

        // Handle OneShotActivated events (one-shot modifier key activated)
        // Format from Kanata: {"OneShotActivated":{"key":"lsft","modifiers":"lsft","t":12345}}
        if let oneShotActivated = json["OneShotActivated"] as? [String: Any],
           let key = oneShotActivated["key"] as? String,
           let modifiers = oneShotActivated["modifiers"] as? String,
           let timestamp = oneShotActivated["t"] as? UInt64
        {
            let observedAt = Date()
            if capabilities.isEmpty || capabilities.contains("oneshot-activated") {
                AppLogger.shared.log("⚡ [EventListener] OneShotActivated: \(key) -> \(modifiers)")
                let activation = KanataOneShotActivation(
                    key: key,
                    modifiers: modifiers,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    observedAt: observedAt
                )
                if let handler = oneShotActivatedHandler {
                    await handler(activation)
                }
            } else {
                AppLogger.shared.debug("⚡ [EventListener] OneShotActivated ignored (capability not advertised)")
            }
            return
        }

        // Handle ChordResolved events (chord multi-key combo resolved)
        // Format from Kanata: {"ChordResolved":{"keys":"s+d","action":"esc","t":12345}}
        if let chordResolved = json["ChordResolved"] as? [String: Any],
           let keys = chordResolved["keys"] as? String,
           let action = chordResolved["action"] as? String,
           let timestamp = chordResolved["t"] as? UInt64
        {
            let observedAt = Date()
            if capabilities.isEmpty || capabilities.contains("chord-resolved") {
                AppLogger.shared.log("🎹 [EventListener] ChordResolved: \(keys) -> \(action)")
                let resolution = KanataChordResolution(
                    keys: keys,
                    action: action,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    observedAt: observedAt
                )
                if let handler = chordResolvedHandler {
                    await handler(resolution)
                }
            } else {
                AppLogger.shared.debug("🎹 [EventListener] ChordResolved ignored (capability not advertised)")
            }
            return
        }

        // Handle TapDanceResolved events (tap-dance resolved to action)
        // Format from Kanata: {"TapDanceResolved":{"key":"q","tap_count":2,"action":"alt+tab","t":12345}}
        if let tapDanceResolved = json["TapDanceResolved"] as? [String: Any],
           let key = tapDanceResolved["key"] as? String,
           let tapCount = tapDanceResolved["tap_count"] as? UInt8,
           let action = tapDanceResolved["action"] as? String,
           let timestamp = tapDanceResolved["t"] as? UInt64
        {
            let observedAt = Date()
            if capabilities.isEmpty || capabilities.contains("tap-dance-resolved") {
                AppLogger.shared.log("💃 [EventListener] TapDanceResolved: \(key) x\(tapCount) -> \(action)")
                let resolution = KanataTapDanceResolution(
                    key: key,
                    tapCount: tapCount,
                    action: action,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    observedAt: observedAt
                )
                if let handler = tapDanceResolvedHandler {
                    await handler(resolution)
                }
            } else {
                AppLogger.shared.debug("💃 [EventListener] TapDanceResolved ignored (capability not advertised)")
            }
            return
        }

        // Handle HrmTrace events (per-decision home-row-mods telemetry)
        if let payload = json["HrmTrace"] {
            do {
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                let trace = try JSONDecoder()
                    .decode(KanataHrmTraceEvent.self, from: payloadData)
                    .withTimestamp(Date())
                if let handler = hrmTraceHandler {
                    await handler(trace)
                }
            } catch {
                AppLogger.shared.debug("🌐 [EventListener] Failed to decode HrmTrace: \(error.localizedDescription)")
            }
            return
        }

        // Handle subscribe ack/errors explicitly to avoid noisy "unhandled" logs.
        if isAwaitingHrmTraceSubscribeAck, let status = json["status"] as? String {
            let normalized = status.lowercased()
            if normalized == "ok" {
                isAwaitingHrmTraceSubscribeAck = false
                isHrmTraceSubscribed = true
                AppLogger.shared.debug("🌐 [EventListener] HrmTrace subscribe acknowledged")
                return
            }
            if normalized == "error" {
                isAwaitingHrmTraceSubscribeAck = false
                let message = json["msg"] as? String ?? "unknown error"
                AppLogger.shared.warn("🌐 [EventListener] HrmTrace subscribe rejected: \(message)")
                return
            }
        }

        AppLogger.shared.debug("🌐 [EventListener] Unhandled message type")
    }

    private func subscribeToHrmTraceIfSupported() async {
        guard !isHrmTraceSubscribed else { return }
        guard capabilities.contains("hrm-trace") else { return }
        guard hrmTraceHandler != nil else { return }
        guard let activeConnection else { return }

        do {
            isAwaitingHrmTraceSubscribeAck = true
            try await send(jsonObject: ["SubscribeHrmTrace": [:] as [String: String]], over: activeConnection)
            AppLogger.shared.debug("🌐 [EventListener] Requested HrmTrace subscription")
        } catch {
            isAwaitingHrmTraceSubscribeAck = false
            // Failing this subscribe should not break layer/key event listening.
            AppLogger.shared.debug("🌐 [EventListener] HrmTrace subscribe failed: \(error.localizedDescription)")
        }
    }

    static func normalizedCapabilities(_ capabilities: [String]) -> [String] {
        var set = Set<String>()
        for capability in capabilities {
            let normalized = capability
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty else { continue }
            set.insert(normalized)
        }
        return set.sorted()
    }

    static func extractMessagePushMessages(from push: [String: Any]) -> [String]? {
        // Prefer canonical field name used by current kanata.
        if let messages = normalizeMessagePushField(push["message"]) {
            return messages
        }

        // Backward compatibility for older/alternate field naming.
        if let messages = normalizeMessagePushField(push["msg"]) {
            return messages
        }

        return nil
    }

    private static func normalizeMessagePushField(_ value: Any?) -> [String]? {
        if let message = value as? String {
            return [message]
        }

        if let messageArray = value as? [String] {
            return messageArray
        }

        if let mixedArray = value as? [Any] {
            let strings = mixedArray.compactMap { $0 as? String }
            return strings.isEmpty ? nil : strings
        }

        return nil
    }

    enum ListenerError: Error {
        case connectionClosed
    }
}

// MARK: - Backward Compatibility

/// Deprecated: Use KanataEventListener instead
@available(*, deprecated, renamed: "KanataEventListener")
typealias LayerChangeListener = KanataEventListener

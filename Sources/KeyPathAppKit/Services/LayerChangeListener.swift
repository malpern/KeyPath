import Foundation
import KeyPathCore
import Network

/// Monitors Kanata's TCP server for layer change notifications.
/// Emits events whenever the server sends either `LayerChange` or `CurrentLayerName`.
actor LayerChangeListener {
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var port: Int?
    private var handler: (@Sendable (String) async -> Void)?
    private let listenerQueue = DispatchQueue(label: "com.keypath.layer-listener")

    func start(port: Int, onLayerChange: @escaping @Sendable (String) async -> Void) async {
        if self.port == port, listenTask != nil { return }
        await stop()
        self.port = port
        handler = onLayerChange // Set handler AFTER stop() to avoid it being cleared
        AppLogger.shared.log("🌐 [LayerListener] Starting layer listener on port \(port)")
        listenTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await listenLoop()
        }
    }

    func stop() async {
        AppLogger.shared.log("🌐 [LayerListener] Stopping layer listener")
        listenTask?.cancel()
        listenTask = nil
        pollTask?.cancel()
        pollTask = nil
        port = nil
        handler = nil
    }

    private func listenLoop() async {
        guard let port else { return }
        while !Task.isCancelled {
            do {
                try await connectAndStream(port: port)
            } catch {
                AppLogger.shared.debug("🌐 [LayerListener] stream ended: \(error.localizedDescription)")
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
        AppLogger.shared.log("🌐 [LayerListener] Connected to kanata TCP server")

        AppLogger.shared.log("🌐 [LayerListener] Sending Hello message")
        try await send(jsonObject: ["Hello": [:] as [String: String]], over: connection)

        AppLogger.shared.log("🌐 [LayerListener] Sending RequestCurrentLayerName message")
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
        AppLogger.shared.debug("🌐 [LayerListener] Received line: '\(line)'")

        guard let handler else {
            AppLogger.shared.debug("🌐 [LayerListener] No handler set, ignoring message")
            return
        }

        guard let data = line.data(using: .utf8) else {
            AppLogger.shared.log("🌐 [LayerListener] Failed to convert line to UTF8 data")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.shared.log("🌐 [LayerListener] Failed to parse JSON from: '\(line)'")
            return
        }

        AppLogger.shared.debug("🌐 [LayerListener] Parsed JSON keys: \(json.keys.joined(separator: ", "))")

        if let layer = json["LayerChange"] as? [String: Any], let new = layer["new"] as? String {
            AppLogger.shared.log("🌐 [LayerListener] Layer change -> \(new)")
            await handler(new)
            return
        }

        if let current = json["CurrentLayerName"] as? [String: Any],
           let name = current["name"] as? String
        {
            AppLogger.shared.debug("🌐 [LayerListener] Current layer -> \(name)")
            await handler(name)
            return
        }

        AppLogger.shared.debug(
            "🌐 [LayerListener] Message not recognized as LayerChange or CurrentLayerName")
    }

    enum ListenerError: Error {
        case connectionClosed
    }
}

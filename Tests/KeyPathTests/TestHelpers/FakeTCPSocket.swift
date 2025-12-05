import Foundation
import Network
@testable import KeyPathAppKit

/// Fake TCP socket for testing KanataTCPClient without a real server
@MainActor
final class FakeTCPSocket {
    let port: Int = 37001
    private var responseQueue: [Data] = []
    var shouldFailConnection: Bool = false
    var shouldTimeout: Bool = false
    var responseDelay: TimeInterval = 0.0
    var chunkSize: Int? = nil
    var shouldDropConnection: Bool = false
    private(set) var readCount: Int = 0
    private(set) var sentData: [Data] = []

    // MARK: - Response Queueing

    func queueResponse(_ response: String) {
        responseQueue.append(Data(response.utf8))
    }

    func queueResponse(_ data: Data) {
        responseQueue.append(data)
    }

    func queueResponses(_ responses: [String]) {
        for response in responses {
            queueResponse(response)
        }
    }

    func clearResponses() {
        responseQueue.removeAll()
    }

    // MARK: - Pre-configured Scenarios

    func simulateHelloHandshake(version: String = "1.10.0", protocol: Int = 1) {
        queueResponses([
            "{\"status\":\"Ok\"}\n",
            "{\"HelloOk\":{\"version\":\"\(version)\",\"protocol\":\(`protocol`),\"capabilities\":[\"reload\",\"validate\"]}}\n"
        ])
    }

    func simulateValidationSuccess() {
        queueResponses([
            "{\"status\":\"Ok\"}\n",
            "{\"ValidationResult\":{\"errors\":[],\"warnings\":[]}}\n"
        ])
    }

    func simulateValidationFailure(errors: [String]) {
        let errorItems = errors.map { error in
            "{\"code\":\"parse_error\",\"message\":\"\(error)\",\"line\":1}"
        }.joined(separator: ",")

        queueResponses([
            "{\"status\":\"Ok\"}\n",
            "{\"ValidationResult\":{\"errors\":[\(errorItems)],\"warnings\":[]}}\n"
        ])
    }

    func simulateReloadSuccess(durationMs: UInt64 = 150) {
        queueResponses([
            "{\"status\":\"Ok\"}\n",
            "{\"ReloadResult\":{\"ready\":true,\"timeout_ms\":5000,\"duration_ms\":\(durationMs)}}\n"
        ])
    }

    func simulateReloadTimeout() {
        queueResponses([
            "{\"status\":\"Ok\"}\n",
            "{\"ReloadResult\":{\"ready\":false,\"timeout_ms\":5000}}\n"
        ])
    }

    func simulateServerError(message: String) {
        queueResponse("{\"status\":\"Error\",\"msg\":\"\(message)\"}\n")
    }

    func simulateBroadcast(_ broadcast: String) {
        queueResponse(broadcast + "\n")
    }

    // MARK: - Connection Behavior

    func simulateConnectionFailure() {
        shouldFailConnection = true
    }

    func simulateConnectionDrop() {
        shouldDropConnection = true
    }

    func simulateDelay(_ delay: TimeInterval) {
        responseDelay = delay
    }

    func simulatePartialReads(chunkSize: Int) {
        self.chunkSize = chunkSize
    }

    func simulateTimeout() {
        shouldTimeout = true
    }

    // MARK: - Mock Network Operations

    func read() async throws -> Data {
        readCount += 1

        if shouldDropConnection {
            shouldDropConnection = false
            throw FakeTCPError.connectionDropped
        }

        if shouldTimeout {
            shouldTimeout = false
            throw FakeTCPError.timeout
        }

        if responseDelay > 0 {
            try await Task.sleep(for: .seconds(responseDelay))
            responseDelay = 0.0
        }

        guard !responseQueue.isEmpty else {
            throw FakeTCPError.noDataAvailable
        }

        let response = responseQueue.removeFirst()

        if let chunkSize = chunkSize, response.count > chunkSize {
            let chunk = Data(response.prefix(chunkSize))
            let remaining = Data(response.dropFirst(chunkSize))
            responseQueue.insert(remaining, at: 0)
            return chunk
        }

        return response
    }

    func send(_ data: Data) {
        sentData.append(data)
    }

    func lastSentCommand() -> [String: Any]? {
        guard let last = sentData.last else { return nil }
        return try? JSONSerialization.jsonObject(with: last) as? [String: Any]
    }

    func wasSent(command: String) -> Bool {
        sentData.contains { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return json.keys.contains(command)
        }
    }

    func reset() {
        responseQueue.removeAll()
        sentData.removeAll()
        readCount = 0
        shouldFailConnection = false
        shouldTimeout = false
        shouldDropConnection = false
        responseDelay = 0.0
        chunkSize = nil
    }
}

enum FakeTCPError: Error, LocalizedError {
    case connectionDropped
    case timeout
    case noDataAvailable
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .connectionDropped:
            return "Connection dropped"
        case .timeout:
            return "Read timeout"
        case .noDataAvailable:
            return "No data available to read"
        case .connectionFailed:
            return "Connection failed"
        }
    }
}

@MainActor
struct TCPClientTestHarness {
    let socket: FakeTCPSocket

    init() {
        socket = FakeTCPSocket()
    }

    func reset() {
        socket.reset()
    }
}

final class BufferedReadSimulator {
    private var buffer: Data = Data()

    func addResponses(_ responses: [String]) {
        for response in responses {
            buffer.append(Data(response.utf8))
        }
    }

    func readLine() -> String? {
        guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineEndIndex = buffer.index(after: newlineIndex)
        let line = Data(buffer.prefix(upTo: lineEndIndex))
        buffer = Data(buffer.suffix(from: lineEndIndex))

        return String(data: line, encoding: .utf8)
    }

    var hasMoreData: Bool {
        !buffer.isEmpty
    }

    func reset() {
        buffer.removeAll()
    }
}

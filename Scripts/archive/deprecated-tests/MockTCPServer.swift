import Foundation
import Network

@testable import KeyPathAppKit

/// Shared mock Kanata TCP server implementation for testing
/// Uses NWListener for realistic network testing across all TCP-related tests
actor MockKanataTCPServer {
    private let port: Int
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var isRunning = false

    // Response configuration
    private var shouldSucceed = true
    private var validationErrors: [MockValidationError] = []
    private var responseDelay: TimeInterval = 0
    private var rawResponse: String?

    init(port: Int) {
        self.port = port
    }

    func start() async throws {
        guard !isRunning else { return }

        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.start(queue: DispatchQueue(label: "mock-kanata-server"))
        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }

        listener?.cancel()
        listener = nil

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()

        isRunning = false
    }

    func setValidationResponse(success: Bool, errors: [MockValidationError]) {
        shouldSucceed = success
        validationErrors = errors
        rawResponse = nil
    }

    func setResponseDelay(_ delay: TimeInterval) {
        responseDelay = delay
    }

    func setRawResponse(_ response: String) {
        rawResponse = response
    }

    private func handleConnection(_ connection: NWConnection) async {
        let connectionId = ObjectIdentifier(connection)
        connections[connectionId] = connection

        connection.start(queue: DispatchQueue(label: "mock-connection"))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, _, error in
            Task {
                await self?.processRequest(
                    connection: connection, connectionId: connectionId, data: data, error: error
                )
            }
        }
    }

    private func processRequest(
        connection: NWConnection, connectionId: ObjectIdentifier, data: Data?, error: Error?
    ) async {
        guard error == nil, data != nil else {
            connections.removeValue(forKey: connectionId)
            connection.cancel()
            return
        }

        if responseDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }

        let responseData: Data

        if let rawResponse {
            responseData = rawResponse.data(using: .utf8) ?? Data()
        } else {
            let response = TCPMockResponse(
                success: shouldSucceed,
                errors: shouldSucceed ? nil : validationErrors
            )

            do {
                responseData = try JSONEncoder().encode(response)
            } catch {
                connections.removeValue(forKey: connectionId)
                connection.cancel()
                return
            }
        }

        // Send response and wait for completion before closing connection
        connection.send(
            content: responseData,
            completion: .contentProcessed { [weak self] _ in
                // Clean up connection after send completes
                self?.connections.removeValue(forKey: connectionId)
                connection.cancel()
            }
        )
    }
}

// MARK: - Mock Data Structures

struct MockValidationError: Codable {
    let line: Int
    let column: Int
    let message: String
}

struct TCPMockResponse: Codable {
    let success: Bool
    let errors: [MockValidationError]?
}

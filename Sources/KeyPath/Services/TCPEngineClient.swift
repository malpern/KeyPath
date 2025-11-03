import Foundation

/// Default EngineClient implementation using the TCP transport.
final class TCPEngineClient: EngineClient, @unchecked Sendable {
    private let timeout: TimeInterval
    private static let requiredCapabilities = ["reload", "status", "validate"]

    init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    func reloadConfig() async -> EngineReloadResult {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port, timeout: timeout)
        // Enforce handshake once before reload
        do {
            try await client.enforceMinimumCapabilities(required: Self.requiredCapabilities)
        } catch {
            return .failure(error: "Kanata update required for TCP protocol: \(error)", response: "")
        }
        let tcp = await client.reloadConfig()
        return mapTCP(tcp)
    }

    // Expose Status to diagnostics callers without exposing the raw client
    func getStatus() async -> Result<KanataTCPClient.TcpStatusInfo, Error> {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port, timeout: timeout)
        do {
            try await client.enforceMinimumCapabilities(required: Self.requiredCapabilities)
            let status = try await client.getStatus()
            return .success(status)
        } catch {
            return .failure(error)
        }
    }

    private func mapTCP(_ result: TCPReloadResult) -> EngineReloadResult {
        switch result {
        case let .success(response: resp): .success(response: resp)
        case let .failure(error: err, response: resp): .failure(error: err, response: resp)
        case .authenticationRequired: .authenticationRequired
        case let .networkError(err): .networkError(err)
        }
    }
}

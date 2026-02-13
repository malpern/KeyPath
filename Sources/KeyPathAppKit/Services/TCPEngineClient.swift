import Foundation

/// Default EngineClient implementation using the TCP transport.
final class TCPEngineClient: EngineClient, @unchecked Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    func reloadConfig() async -> EngineReloadResult {
        let timeout = self.timeout
        return await EngineReloadSingleFlight.shared.run(reason: "TCPEngineClient.reloadConfig") {
            let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
            let client = KanataTCPClient(port: port, timeout: timeout)
            let tcp = await client.reloadConfig()

            // Always close to avoid leaking descriptors and to reduce server-side BrokenPipe spam.
            await client.cancelInflightAndCloseConnection()

            return self.mapTCP(tcp)
        }
    }

    private func mapTCP(_ result: TCPReloadResult) -> EngineReloadResult {
        switch result {
        case let .success(response: resp): .success(response: resp)
        case let .failure(error: err, response: resp): .failure(error: err, response: resp)
        case let .networkError(err): .networkError(err)
        }
    }
}

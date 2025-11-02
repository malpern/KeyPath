import Foundation

/// Default EngineClient implementation using the TCP transport.
final class TCPEngineClient: EngineClient {
    private let client: KanataTCPClient

    init(port: Int = PreferencesService.shared.tcpServerPort, timeout: TimeInterval = 5.0) {
        client = KanataTCPClient(port: port, timeout: timeout)
    }

    func reloadConfig() async -> TCPReloadResult {
        await client.reloadConfig()
    }
}



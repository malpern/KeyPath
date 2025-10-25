import Foundation

/// Singleton service providing shared access to TCP client
actor SharedTCPClientService {
    static let shared = SharedTCPClientService()

    private var client: KanataTCPClient?

    private init() {}

    /// Get or create TCP client for the configured port
    func getClient() -> KanataTCPClient {
        let port = PreferencesService().tcpServerPort

        if let existing = client {
            // Return existing client (TCP maintains persistent connections)
            return existing
        }

        let newClient = KanataTCPClient(port: port)
        client = newClient
        return newClient
    }

    /// Close and reset the client (forces reconnection on next use)
    func resetClient() async {
        // TCP creates fresh connections for each request, so just clear the client
        client = nil
    }
}

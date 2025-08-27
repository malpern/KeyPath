import Foundation

/// Shared UDP client service to prevent session conflicts
/// Ensures single KanataUDPClient instance per port to maintain session consistency
@MainActor
class SharedUDPClientService: ObservableObject {
    static let shared = SharedUDPClientService()

    private var clients: [Int: KanataUDPClient] = [:]

    private init() {}

    /// Get or create a UDP client for the specified port
    /// Reuses existing client to maintain session continuity
    func getClient(port: Int) -> KanataUDPClient {
        if let existingClient = clients[port] {
            AppLogger.shared.log("🔄 [SharedUDPService] Reusing existing UDP client for port \(port)")
            return existingClient
        }

        AppLogger.shared.log("🆕 [SharedUDPService] Creating new UDP client for port \(port)")
        let newClient = KanataUDPClient(port: port)
        clients[port] = newClient
        return newClient
    }

    /// Clear client for specific port (forces recreation on next access)
    func clearClient(port: Int) async {
        if let client = clients[port] {
            AppLogger.shared.log("🧹 [SharedUDPService] Clearing UDP client for port \(port)")
            await client.clearAuthentication()
            clients.removeValue(forKey: port)
        }
    }

    /// Clear all clients (useful for cleanup)
    func clearAllClients() async {
        AppLogger.shared.log("🧹 [SharedUDPService] Clearing all UDP clients")
        for (_, client) in clients {
            await client.clearAuthentication()
        }
        clients.removeAll()
    }

    /// Check if client exists for port
    func hasClient(port: Int) -> Bool {
        return clients[port] != nil
    }
}

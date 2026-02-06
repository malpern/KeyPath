import Foundation

// MARK: - Protocol Models

extension KanataTCPClient {
    struct TcpHelloOk: Codable, Sendable {
        let version: String
        let protocolVersion: Int
        let capabilities: [String]
        let request_id: UInt64?

        enum CodingKeys: String, CodingKey {
            case version
            case protocolVersion = "protocol"
            case capabilities
            case request_id
            // Minimal server compatibility
            case server
        }

        init(version: String, protocolVersion: Int, capabilities: [String], request_id: UInt64? = nil) {
            self.version = version
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.request_id = request_id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            request_id = try container.decodeIfPresent(UInt64.self, forKey: .request_id)

            if let version = try container.decodeIfPresent(String.self, forKey: .version),
               let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion),
               let capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities)
            {
                self.version = version
                self.protocolVersion = protocolVersion
                self.capabilities = capabilities
                return
            }

            // Minimal form: { "HelloOk": { "server": "kanata", "capabilities": [..] } }
            let serverString = try (container.decodeIfPresent(String.self, forKey: .server)) ?? "kanata"
            let caps = try (container.decodeIfPresent([String].self, forKey: .capabilities)) ?? []
            version = serverString
            protocolVersion = 1
            capabilities = caps
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(capabilities, forKey: .capabilities)
        }

        func hasCapabilities(_ required: [String]) -> Bool {
            let set = Set(capabilities)
            return required.allSatisfy { set.contains($0) }
        }
    }

    struct TcpLastReload: Codable, Sendable {
        let ok: Bool
        let at: String?
        let duration_ms: UInt64?
        let epoch: UInt64?
    }

    struct TcpStatusInfo: Codable, Sendable {
        let engine_version: String?
        let uptime_s: UInt64?
        let ready: Bool
        let last_reload: TcpLastReload?
        let request_id: UInt64?
    }

    struct TcpLayerNames: Codable, Sendable {
        let names: [String]
        let request_id: UInt64?
    }

    struct ReloadResult: Codable {
        let ready: Bool
        let timeout_ms: UInt32
        let ok: Bool?
        let duration_ms: UInt64?
        let epoch: UInt64?
        let request_id: UInt64?
    }

    /// Action types for fake key commands
    enum FakeKeyAction: String, Sendable {
        case press = "Press"
        case release = "Release"
        case tap = "Tap"
        case toggle = "Toggle"
    }

    /// Result of acting on a fake key
    enum FakeKeyResult: Sendable {
        case success
        case error(String)
        case networkError(String)
    }

    /// Result of changing a layer
    enum ChangeLayerResult: Sendable {
        case success
        case error(String)
        case networkError(String)
    }
}

import Foundation

// MARK: - Kanata TCP Protocol Models
//
// These types mirror the Rust enums in External/kanata/tcp_protocol/src/lib.rs
// to ensure type-safe communication with Kanata's TCP server.

/// Messages sent from KeyPath to Kanata's TCP server
enum TCPClientMessage: Codable {
    case reload
    case reloadNext
    case requestCurrentLayerName

    enum CodingKeys: String, CodingKey {
        case reload = "Reload"
        case reloadNext = "ReloadNext"
        case requestCurrentLayerName = "RequestCurrentLayerName"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .reload:
            try container.encode(EmptyObject(), forKey: .reload)
        case .reloadNext:
            try container.encode(EmptyObject(), forKey: .reloadNext)
        case .requestCurrentLayerName:
            try container.encode(EmptyObject(), forKey: .requestCurrentLayerName)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.reload) {
            self = .reload
        } else if container.contains(.reloadNext) {
            self = .reloadNext
        } else if container.contains(.requestCurrentLayerName) {
            self = .requestCurrentLayerName
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown client message type")
            )
        }
    }
}

/// Responses from Kanata TCP server (status responses)
enum TCPServerResponse: Codable {
    case ok
    case error(msg: String)

    enum CodingKeys: String, CodingKey {
        case status
        case msg
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ok:
            try container.encode("Ok", forKey: .status)
        case .error(let msg):
            try container.encode("Error", forKey: .status)
            try container.encode(msg, forKey: .msg)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "Ok":
            self = .ok
        case "Error":
            let msg = try container.decode(String.self, forKey: .msg)
            self = .error(msg: msg)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown status: \(status)"
                )
            )
        }
    }
}

/// Broadcast messages from Kanata TCP server (informational events)
enum TCPServerMessage: Codable {
    case layerChange(new: String)
    case currentLayerName(name: String)
    case configFileReload(new: String)
    case configFileReloadNew(new: String)

    enum CodingKeys: String, CodingKey {
        case layerChange = "LayerChange"
        case currentLayerName = "CurrentLayerName"
        case configFileReload = "ConfigFileReload"
        case configFileReloadNew = "ConfigFileReloadNew"
    }

    enum LayerChangeKeys: String, CodingKey {
        case new
    }

    enum CurrentLayerNameKeys: String, CodingKey {
        case name
    }

    enum ConfigFileReloadKeys: String, CodingKey {
        case new
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .layerChange(let new):
            var nested = container.nestedContainer(keyedBy: LayerChangeKeys.self, forKey: .layerChange)
            try nested.encode(new, forKey: .new)

        case .currentLayerName(let name):
            var nested = container.nestedContainer(keyedBy: CurrentLayerNameKeys.self, forKey: .currentLayerName)
            try nested.encode(name, forKey: .name)

        case .configFileReload(let new):
            var nested = container.nestedContainer(keyedBy: ConfigFileReloadKeys.self, forKey: .configFileReload)
            try nested.encode(new, forKey: .new)

        case .configFileReloadNew(let new):
            var nested = container.nestedContainer(keyedBy: ConfigFileReloadKeys.self, forKey: .configFileReloadNew)
            try nested.encode(new, forKey: .new)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.layerChange) {
            let nested = try container.nestedContainer(keyedBy: LayerChangeKeys.self, forKey: .layerChange)
            let new = try nested.decode(String.self, forKey: .new)
            self = .layerChange(new: new)

        } else if container.contains(.currentLayerName) {
            let nested = try container.nestedContainer(keyedBy: CurrentLayerNameKeys.self, forKey: .currentLayerName)
            let name = try nested.decode(String.self, forKey: .name)
            self = .currentLayerName(name: name)

        } else if container.contains(.configFileReload) {
            let nested = try container.nestedContainer(keyedBy: ConfigFileReloadKeys.self, forKey: .configFileReload)
            let new = try nested.decode(String.self, forKey: .new)
            self = .configFileReload(new: new)

        } else if container.contains(.configFileReloadNew) {
            let nested = try container.nestedContainer(keyedBy: ConfigFileReloadKeys.self, forKey: .configFileReloadNew)
            let new = try nested.decode(String.self, forKey: .new)
            self = .configFileReloadNew(new: new)

        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown server message type")
            )
        }
    }
}

/// Empty object for encoding messages with no payload
private struct EmptyObject: Codable {}

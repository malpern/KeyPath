import Foundation

/// A quick launch mapping (simplified, self-contained version)
struct QuickLaunchMapping: Identifiable, Codable, Equatable {
    var id: UUID
    var key: String
    var targetType: TargetType
    var targetName: String // App name or URL
    var bundleId: String?
    var isEnabled: Bool

    enum TargetType: String, Codable {
        case app
        case website
    }

    var isApp: Bool {
        targetType == .app
    }

    var displayName: String {
        if targetType == .website {
            return URLMappingFormatter.displayDomain(for: targetName)
        }
        return targetName
    }

    init(id: UUID = UUID(), key: String, targetType: TargetType, targetName: String, bundleId: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.targetType = targetType
        self.targetName = targetName
        self.bundleId = bundleId
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, key, targetType, targetName, bundleId, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        targetType = try container.decode(TargetType.self, forKey: .targetType)
        targetName = try container.decode(String.self, forKey: .targetName)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

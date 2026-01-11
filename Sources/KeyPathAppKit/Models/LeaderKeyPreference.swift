import Foundation

/// System-level preference for the primary leader key
/// This defines which key activates the navigation/leader layer
/// Independent of any collection - collections just declare they target this layer
public struct LeaderKeyPreference: Codable, Equatable, Sendable {
    /// The physical key that activates the leader layer
    public var key: String

    /// The layer that gets activated
    public var targetLayer: RuleCollectionLayer

    /// Whether leader key is enabled at all
    public var enabled: Bool

    /// Default configuration: Space → Nav layer, enabled
    public static let `default` = LeaderKeyPreference(
        key: "space",
        targetLayer: .navigation,
        enabled: true
    )

    public init(key: String, targetLayer: RuleCollectionLayer, enabled: Bool) {
        self.key = key
        self.targetLayer = targetLayer
        self.enabled = enabled
    }
}

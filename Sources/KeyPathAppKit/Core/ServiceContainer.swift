import Foundation

/// Central service container created once in App.init() and passed through the view hierarchy.
///
/// This is NOT a singleton — it's instantiated explicitly in the composition root and injected
/// via SwiftUI Environment. Default parameter values point to `.shared` for backward compatibility
/// during incremental migration. Tests can pass mock instances.
///
/// **Usage in views:**
/// ```swift
/// @Environment(\.services) private var services
/// // then: services.preferences, services.appKeymapStore, etc.
/// ```
@MainActor
@Observable
final class ServiceContainer {
    let preferences: PreferencesService
    let appKeymapStore: AppKeymapStore
    let ruleCollectionStore: RuleCollectionStore
    let iconResolver: IconResolverService
    let faviconFetcher: FaviconFetcher

    init(
        preferences: PreferencesService = .shared,
        appKeymapStore: AppKeymapStore = .shared,
        ruleCollectionStore: RuleCollectionStore = .shared,
        iconResolver: IconResolverService = .shared,
        faviconFetcher: FaviconFetcher = .shared
    ) {
        self.preferences = preferences
        self.appKeymapStore = appKeymapStore
        self.ruleCollectionStore = ruleCollectionStore
        self.iconResolver = iconResolver
        self.faviconFetcher = faviconFetcher
    }
}

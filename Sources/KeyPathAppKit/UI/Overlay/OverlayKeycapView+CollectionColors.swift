import SwiftUI

extension OverlayKeycapView {
    // MARK: - Collection Colors

    /// Color palette for collection-specific key backgrounds in layer mode
    private enum LayerColors {
        /// Default orange for layer mode keys (Vim, unknown collections)
        static let defaultLayer = Color(red: 0.85, green: 0.45, blue: 0.15)
        /// Vim navigation collection keys
        static let vim = Color(red: 0.85, green: 0.45, blue: 0.15)
        /// Window snapping collection keys
        static let windowSnapping = Color.purple
        /// Symbol layer collection keys (future)
        static let symbols = Color.blue
        /// Launcher collection keys (future)
        static let launcher = Color.cyan
    }

    /// Determine key color based on collection ownership
    /// - Parameter collectionId: The UUID of the collection owning this key, or nil for default
    /// - Returns: The color to use for this key's background
    /// - Note: Internal for testing
    func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            // No collection info - use default layer mode orange
            return LayerColors.defaultLayer
        }

        // Map collection UUIDs to colors
        switch id {
        case RuleCollectionIdentifier.vimNavigation:
            return LayerColors.vim
        case RuleCollectionIdentifier.windowSnapping:
            return LayerColors.windowSnapping
        case RuleCollectionIdentifier.symbolLayer:
            return LayerColors.symbols
        case RuleCollectionIdentifier.launcher:
            return LayerColors.launcher
        default:
            // Unknown collection - default orange
            return LayerColors.defaultLayer
        }
    }
}

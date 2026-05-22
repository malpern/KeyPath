import SwiftUI

extension OverlayKeycapView {
    // MARK: - Collection Colors

    /// Color palette for collection-specific key backgrounds in layer mode
    private enum LayerColors {
        static let defaultLayer = KeyPathColors.layerOrange
        static let vim = KeyPathColors.layerOrange
        static let windowSnapping = Color.purple
        static let symbols = Color.blue
        static let launcher = Color.cyan
        static let neovimTerminal = KeyPathColors.layerBlue
        static let vallackNav = KeyPathColors.layerGreen
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
        case RuleCollectionIdentifier.neovimTerminal:
            return LayerColors.neovimTerminal
        case RuleCollectionIdentifier.vallackNavigation:
            return LayerColors.vallackNav
        default:
            // Unknown collection - default orange
            return LayerColors.defaultLayer
        }
    }
}

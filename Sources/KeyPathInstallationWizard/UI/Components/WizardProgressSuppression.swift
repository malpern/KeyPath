import SwiftUI

/// Preference + helper modifier to let wizard pages signal that they already show
/// a visible, inline progress indicator (so the global overlay can be suppressed).
///
/// This avoids the "two blue bars at once" problem: when a page has contextual progress,
/// we don't also show the full-page operation overlay.
public struct WizardInlineProgressVisiblePreferenceKey: PreferenceKey {
    public static let defaultValue: Bool = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Marks that this view subtree contains an inline progress indicator that is currently visible.
    /// The wizard root uses this to hide the global operation overlay.
    public func wizardInlineProgressVisible(_ isVisible: Bool = true) -> some View {
        preference(key: WizardInlineProgressVisiblePreferenceKey.self, value: isVisible)
    }
}

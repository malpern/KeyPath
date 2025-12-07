import SwiftUI

/// PreferenceKey for communicating ideal window height from SwiftUI views to AppKit
struct WindowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 400

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension Notification.Name {
    /// Posted when the main window's content height changes
    static let mainWindowHeightChanged = Notification.Name("MainWindowHeightChanged")
}

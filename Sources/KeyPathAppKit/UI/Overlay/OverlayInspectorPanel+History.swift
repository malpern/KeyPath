import SwiftUI

extension OverlayInspectorPanel {
    var historyContent: some View {
        KeystrokeHistoryView(isDark: isDark)
    }
}

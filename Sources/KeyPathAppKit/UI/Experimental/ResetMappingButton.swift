import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Reset Mapping Button

/// Toolbar button that resets current mapping on single click, shows reset all confirmation on double click.
struct ResetMappingButton: View {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?
    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Button {
            // Handle via gesture below for double-click support
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .help("Click: Reset mapping. Double-click: Reset all to defaults")
        .accessibilityIdentifier("mapper-reset-button")
        .accessibilityLabel("Reset mapping")
        .simultaneousGesture(
            TapGesture().onEnded {
                clickCount += 1

                if clickCount == 1 {
                    clickTimer = Timer.scheduledTimer(withTimeInterval: doubleClickDelay, repeats: false) { _ in
                        Task { @MainActor in
                            if clickCount == 1 {
                                onSingleClick()
                            }
                            clickCount = 0
                        }
                    }
                } else if clickCount >= 2 {
                    clickTimer?.invalidate()
                    clickTimer = nil
                    clickCount = 0
                    onDoubleClick()
                }
            }
        )
    }
}

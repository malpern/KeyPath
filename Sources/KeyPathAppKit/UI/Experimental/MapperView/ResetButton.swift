import Foundation
import SwiftUI

/// Button that supports single-click (reset current) and double-click (reset all).
/// Uses a short timer to differentiate between single and double clicks.
struct ResetButton: View {
    let isEnabled: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?

    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Button {
            guard isEnabled else { return }
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
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
        )
        .opacity(isEnabled ? 1.0 : 0.3)
        .contentShape(Rectangle())
        .help("Click: Reset mapping. Double-click: Reset all to defaults")
    }
}

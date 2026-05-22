import AppKit
import SwiftUI

struct WindowControlsView: View {
    var body: some View {
        HStack(spacing: 8) {
            controlCircle(color: KeyPathColors.windowClose) {
                NSApp.keyWindow?.performClose(nil)
            }
            controlCircle(color: KeyPathColors.windowMinimize) {
                NSApp.keyWindow?.performMiniaturize(nil)
            }
            controlCircle(color: KeyPathColors.windowZoom) {
                NSApp.keyWindow?.performZoom(nil)
            }
        }
        .padding(.leading, 6)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
    }

    private func controlCircle(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

import AppKit
import SwiftUI

struct WindowControlsView: View {
  var body: some View {
    HStack(spacing: 8) {
      controlCircle(color: Color(red: 0.99, green: 0.35, blue: 0.31)) {
        NSApp.keyWindow?.performClose(nil)
      }
      controlCircle(color: Color(red: 0.99, green: 0.77, blue: 0.26)) {
        NSApp.keyWindow?.performMiniaturize(nil)
      }
      controlCircle(color: Color(red: 0.30, green: 0.85, blue: 0.39)) {
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

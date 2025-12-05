import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Toast View (shared with ContentView)

struct ToastView: View {
    let message: String
    let type: KanataViewModel.ToastType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }

    private var iconName: String {
        switch type {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch type {
        case .success: .green
        case .error: .red
        case .info: .blue
        case .warning: .orange
        }
    }
}

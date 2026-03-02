import SwiftUI

/// A small "?" icon that shows explanatory text in a popover on hover.
struct InfoTip: View {
    let text: String

    @State private var isHovering = false
    @State private var isPresented = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    isPresented = true
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 240)
                    .padding(10)
            }
            .onChange(of: isPresented) { _, presented in
                // When popover is dismissed externally (click away), only re-show
                // after the cursor leaves and re-enters the icon.
                if !presented {
                    isHovering = false
                }
            }
            .accessibilityLabel(text)
    }
}

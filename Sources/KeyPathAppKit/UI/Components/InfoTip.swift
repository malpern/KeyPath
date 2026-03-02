import SwiftUI

/// A small "?" icon that shows explanatory text in a popover on hover.
struct InfoTip: View {
    let text: String

    @State private var isHovering = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 240)
                    .padding(10)
            }
            .accessibilityLabel(text)
    }
}

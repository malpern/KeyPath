import SwiftUI

/// Symbol grid for the Context HUD symbol layer
struct ContextHUDSymbolView: View {
    let entries: [HUDKeyEntry]

    private let columns = [
        GridItem(.adaptive(minimum: 40, maximum: 56), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entries) { entry in
                SymbolCell(entry: entry)
            }
        }
        .accessibilityLabel("Symbol picker")
    }
}

/// A single symbol cell showing the symbol and its trigger key
private struct SymbolCell: View {
    let entry: HUDKeyEntry

    var body: some View {
        VStack(spacing: 2) {
            // Symbol character
            Text(entry.action)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)

            // Trigger key
            Text(entry.keycap)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.7))
        }
        .frame(width: 40)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 0.5)
        )
    }
}

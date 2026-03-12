import SwiftUI

/// Compact summary row for modifier-specific rule variants, e.g. a custom Shift action.
struct RuleModifierVariantView: View {
    let label: String
    let output: String
    var accentColor: Color = .orange

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(0.14))
                )

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(KeyDisplayFormatter.formatSequence(output))
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

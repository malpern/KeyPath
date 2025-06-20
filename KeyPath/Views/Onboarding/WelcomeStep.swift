import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to KeyPath")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            Text("KeyPath helps you create custom keyboard remappings using natural language and AI.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "message.fill",
                    title: "Natural Language",
                    description: "Describe your remapping in plain English"
                )

                FeatureRow(
                    icon: "cpu",
                    title: "AI-Powered",
                    description: "Claude Sonnet 4 understands your intent"
                )

                FeatureRow(
                    icon: "checkmark.shield.fill",
                    title: "Safe & Validated",
                    description: "All rules are validated before installation"
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.vertical, 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
        }
        .padding(.vertical, 4)
    }
}

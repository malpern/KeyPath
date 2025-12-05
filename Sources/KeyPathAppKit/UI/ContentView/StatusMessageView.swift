import SwiftUI

struct StatusMessageView: View {
    let message: String
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon with white circle background
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)

                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(messageTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let subtitle = messageSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .transition(.opacity)
    }

    private var messageTitle: String {
        message.components(separatedBy: "\n").first ?? message
    }

    private var messageSubtitle: String? {
        let lines = message.components(separatedBy: "\n")
        return lines.count > 1 ? lines[1] : nil
    }

    private var iconName: String {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            "xmark.circle.fill"
        } else if message.contains("paused") {
            "pause.circle.fill"
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") {
            "exclamationmark.triangle.fill"
        } else {
            "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            .red
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            .orange
        } else {
            .green
        }
    }

    private var backgroundColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.85)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            Color.orange.opacity(0.85)
        } else {
            Color.green.opacity(0.85)
        }
    }

    private var borderColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.5)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            Color.orange.opacity(0.5)
        } else {
            Color.green.opacity(0.5)
        }
    }
}

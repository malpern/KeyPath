import SwiftUI

struct FormattedLine {
    let id = UUID()
    let view: AnyView
}

func formatTextWithBullets(_ text: String) -> [FormattedLine] {
    let lines = text.components(separatedBy: .newlines)
    var result: [FormattedLine] = []

    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.isEmpty {
            // Empty line - add some spacing
            result.append(FormattedLine(view: AnyView(Spacer().frame(height: 4))))
        } else if trimmedLine.hasPrefix("- ") {
            // Bullet point
            let content = String(trimmedLine.dropFirst(2))
            let bulletView = HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                if let attributedString = try? AttributedString(markdown: content) {
                    Text(attributedString)
                } else {
                    Text(content)
                }
                Spacer()
            }
            result.append(FormattedLine(view: AnyView(bulletView)))
        } else {
            // Regular paragraph
            if let attributedString = try? AttributedString(markdown: trimmedLine) {
                result.append(FormattedLine(view: AnyView(Text(attributedString))))
            } else {
                result.append(FormattedLine(view: AnyView(Text(trimmedLine))))
            }
        }
    }

    return result
}

struct KeyPathMessageView: View {
    let message: KeyPathMessage
    let isResponding: Bool
    let onInstallRule: ((KanataRule) -> Void)?

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text(message.displayText)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if message.displayText.isEmpty && isResponding {
                        PulsingDotView()
                            .frame(width: 60, height: 25)
                    } else {
                        switch message.type {
                        case .text(let text):
                            if text == "LOGO_VIEW" {
                                // Show animated welcome logo
                                HStack {
                                    WelcomeLogoView()
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            } else if text.contains("- **") {
                                // Handle bullet points manually for better formatting
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(formatTextWithBullets(text), id: \.id) { line in
                                        line.view
                                    }
                                }
                                .textSelection(.enabled)
                            } else if let attributedString = try? AttributedString(markdown: text) {
                                Text(attributedString)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                            } else {
                                Text(text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                            }
                        case .rule(let rule):
                            if let onInstallRule = onInstallRule {
                                RuleMessageView(rule: rule) {
                                    onInstallRule(rule)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, message.role == .assistant ? 4 : 8)
                Spacer()
            }
        }
        .padding(.vertical, message.role == .assistant ? 2 : 6)
    }
}

/// Animated loading indicator shown while AI is generating a response
struct PulsingDotView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.primary.opacity(0.5))
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}

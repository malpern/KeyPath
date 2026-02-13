import SwiftUI

/// Shared indeterminate activity treatment for wizard flows.
///
/// This is the single "thinking" language used across overlays, headers, and inline loading views.
struct WizardActivityIndicator: View {
    let message: String?
    let width: CGFloat
    let height: CGFloat

    init(message: String? = nil, width: CGFloat = 200, height: CGFloat = 6) {
        self.message = message
        self.width = width
        self.height = height
    }

    var body: some View {
        VStack(spacing: 10) {
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(NSColor.separatorColor).opacity(0.35))
                    .frame(width: width, height: height)

                IndeterminateProgressBar()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: height / 2))
            }
            .frame(width: width, height: height)
        }
    }
}

/// A reusable progress indicator component for wizard operations
struct WizardProgressIndicator: View {
    let title: String
    let progress: Double
    let isIndeterminate: Bool

    init(title: String, progress: Double = 0.0, isIndeterminate: Bool = false) {
        self.title = title
        self.progress = progress
        self.isIndeterminate = isIndeterminate
    }

    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.separatorColor).opacity(0.3))
                        .frame(height: 8)

                    if isIndeterminate {
                        // Indeterminate animation
                        IndeterminateProgressBar()
                            .frame(height: 8)
                    } else {
                        // Determinate progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(max(progress, 0.0), 1.0), height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
            }
            .frame(height: 8)

            // Title and percentage
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                if !isIndeterminate {
                    Text(String(localized: "\(Int(progress * 100))%"))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                )
        )
    }
}

/// Indeterminate progress animation
struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.blue.opacity(0.0), location: 0.0),
                            .init(color: Color.blue.opacity(0.8), location: 0.25),
                            .init(color: Color.blue, location: 0.5),
                            .init(color: Color.blue.opacity(0.8), location: 0.75),
                            .init(color: Color.blue.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * 0.3)
                .offset(x: geometry.size.width * offset)
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                    ) {
                        offset = 1.0
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Operation progress overlay that shows during long-running operations
struct WizardOperationProgress: View {
    let operationName: String
    let progress: Double
    let isIndeterminate: Bool

    var body: some View {
        WizardActivityIndicator(
            message: operationDisplayName,
            width: 220,
            height: 6
        )
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            )
    }

    private var operationDisplayName: String {
        let trimmed = operationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Working..."
        }
        return trimmed
    }
}

// MARK: - Preview

struct WizardProgressIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            WizardProgressIndicator(
                title: "Installing components",
                progress: 0.45
            )

            WizardProgressIndicator(
                title: "Checking system state",
                isIndeterminate: true
            )

            WizardOperationProgress(
                operationName: "Terminating Conflicting Processes",
                progress: 0.6,
                isIndeterminate: false
            )

            WizardProgressIndicator(
                title: "Completed",
                progress: 1.0
            )
        }
        .padding()
        .frame(width: 500)
    }
}

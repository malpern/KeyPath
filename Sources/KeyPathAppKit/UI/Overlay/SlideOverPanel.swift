import SwiftUI

/// A slide-over panel that covers its parent view with back navigation.
/// Used for progressive disclosure of advanced options without cluttering the main UI.
struct SlideOverPanel<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            header

            Divider()
                .opacity(0.3)

            // Content area
            ScrollView {
                content()
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("slide-over-back-button")
            .accessibilityLabel("Go back")

            Spacer()

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Invisible spacer to center title
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.subheadline)
            }
            .opacity(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Background

    @ViewBuilder
    private var panelBackground: some View {
        // Use solid background to fully cover content behind the panel
        Color(NSColor.windowBackgroundColor)
    }
}

// MARK: - Slide Over Container

/// Container that manages the slide-over state and transition.
/// Wraps the main content and conditionally shows the slide-over panel.
struct SlideOverContainer<MainContent: View, PanelContent: View>: View {
    @Binding var isPresented: Bool
    let panelTitle: String
    @ViewBuilder let mainContent: () -> MainContent
    @ViewBuilder let panelContent: () -> PanelContent

    var body: some View {
        ZStack {
            // Main content (always rendered, but covered when panel is shown)
            mainContent()
                .allowsHitTesting(!isPresented)

            // Slide-over panel
            if isPresented {
                SlideOverPanel(
                    title: panelTitle,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    },
                    content: panelContent
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("SlideOverPanel") {
        struct PreviewWrapper: View {
            @State private var showPanel = false

            var body: some View {
                SlideOverContainer(
                    isPresented: $showPanel,
                    panelTitle: "Customize",
                    mainContent: {
                        VStack {
                            Text("Main Content")
                            Button("Show Panel") {
                                showPanel = true
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.2))
                    },
                    panelContent: {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Panel Content")
                            Text("This is where the action picker would go")
                        }
                    }
                )
                .frame(width: 280, height: 400)
            }
        }

        return PreviewWrapper()
    }
#endif

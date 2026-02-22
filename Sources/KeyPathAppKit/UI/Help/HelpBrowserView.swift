import SwiftUI

// MARK: - Help Topic Model

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let resource: String
    let group: HelpTopicGroup
}

enum HelpTopicGroup: String, CaseIterable {
    case gettingStarted = "Getting Started"
    case features = "Features"
    case reference = "Reference"
    case switchingTools = "Switching Tools"
}

// MARK: - Topic Data

extension HelpTopic {
    static let allTopics: [HelpTopic] = [
        // Getting Started
        HelpTopic(id: "installation", title: "Installation Guide", icon: "shippingbox", resource: "installation", group: .gettingStarted),
        HelpTopic(id: "concepts", title: "Keyboard Concepts", icon: "keyboard", resource: "concepts", group: .gettingStarted),
        HelpTopic(id: "use-cases", title: "What You Can Build", icon: "hammer", resource: "use-cases", group: .gettingStarted),
        // Features
        HelpTopic(id: "home-row-mods", title: "Shortcuts Without Reaching", icon: "hand.raised", resource: "home-row-mods", group: .features),
        HelpTopic(id: "tap-hold", title: "One Key, Multiple Actions", icon: "hand.tap", resource: "tap-hold", group: .features),
        HelpTopic(id: "window-management", title: "Windows & App Shortcuts", icon: "macwindow.on.rectangle", resource: "window-management", group: .features),
        HelpTopic(id: "action-uri", title: "Launching Apps", icon: "link", resource: "action-uri", group: .features),
        HelpTopic(id: "alternative-layouts", title: "Alternative Layouts", icon: "textformat", resource: "alternative-layouts", group: .features),
        HelpTopic(id: "keyboard-layouts", title: "Your Keyboard", icon: "keyboard.badge.ellipsis", resource: "keyboard-layouts", group: .features),
        HelpTopic(id: "kindavim", title: "Full Vim Modes", icon: "v.square", resource: "kindavim", group: .features),
        HelpTopic(id: "neovim-terminal", title: "Neovim in the Terminal", icon: "terminal", resource: "neovim-terminal", group: .features),
        // Reference
        HelpTopic(id: "action-uri-reference", title: "Action URI Reference", icon: "curlybraces", resource: "action-uri-reference", group: .reference),
        HelpTopic(id: "privacy", title: "Privacy & Permissions", icon: "lock.shield", resource: "privacy", group: .reference),
        // Switching Tools
        HelpTopic(id: "karabiner-users", title: "From Karabiner-Elements", icon: "arrow.right.arrow.left", resource: "karabiner-users", group: .switchingTools),
        HelpTopic(id: "kanata-users", title: "From Kanata", icon: "arrow.right.arrow.left", resource: "kanata-users", group: .switchingTools),
    ]

    static func topic(forResource resource: String) -> HelpTopic? {
        allTopics.first { $0.resource == resource }
    }
}

// MARK: - Help Browser View

struct HelpBrowserView: View {
    @State private var selectedTopic: HelpTopic?
    @State private var cardsAppeared = false
    @Environment(\.colorScheme) private var colorScheme

    /// Optional initial topic to select on appear.
    var initialTopic: HelpTopic?

    // MARK: Navigation

    private var currentIndex: Int? {
        guard let topic = selectedTopic else { return nil }
        return HelpTopic.allTopics.firstIndex(of: topic)
    }

    private func navigateForward() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = currentIndex, index + 1 < HelpTopic.allTopics.count {
                selectedTopic = HelpTopic.allTopics[index + 1]
            } else if selectedTopic == nil {
                selectedTopic = HelpTopic.allTopics.first
            }
        }
    }

    private func navigateBack() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = currentIndex {
                selectedTopic = index > 0 ? HelpTopic.allTopics[index - 1] : nil
            }
        }
    }

    private func navigateToIndex(_ index: Int) {
        guard index >= 0, index < HelpTopic.allTopics.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTopic = HelpTopic.allTopics[index]
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .animation(.easeInOut(duration: 0.25), value: selectedTopic)
        }
        .onAppear {
            if let initialTopic {
                selectedTopic = initialTopic
            }
        }
        // Number key navigation (1-9, no modifier)
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            if let digit = press.characters.first?.wholeNumberValue {
                navigateToIndex(digit - 1)
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTopic) {
            // Home button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTopic = nil
                }
            } label: {
                Label("KeyPath Help", systemImage: "square.stack.3d.up.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(HomeButtonStyle())
            .padding(.vertical, 4)
            .accessibilityIdentifier("help-home-button")

            ForEach(HelpTopicGroup.allCases, id: \.self) { group in
                let topics = HelpTopic.allTopics.filter { $0.group == group }
                if !topics.isEmpty {
                    Section(group.rawValue) {
                        ForEach(topics) { topic in
                            Label(topic.title, systemImage: topic.icon)
                                .tag(topic)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(Color(nsColor: .init(red: 0.55, green: 0.42, blue: 0.30, alpha: 1.0)))
        .safeAreaInset(edge: .bottom) {
            footerLinks
        }
        .frame(minWidth: 200)
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 12) {
            Link("KeyPath Website", destination: URL(string: "https://keypath-app.com")!)
            Text("\u{00B7}")
                .foregroundStyle(.secondary)
            Link("Report an Issue", destination: URL(string: "https://github.com/malpern/KeyPath/issues")!)
        }
        .font(.caption)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let topic = selectedTopic {
            VStack(spacing: 0) {
                // Back bar with prev/next
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTopic = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Help")
                                .font(.callout)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .foregroundStyle(.secondary)

                    Spacer()

                    // Prev / Next
                    Button { navigateBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(currentIndex == nil)
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Button { navigateForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(currentIndex.map { $0 + 1 >= HelpTopic.allTopics.count } ?? false)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                MarkdownWebView(
                    resource: topic.resource,
                    colorScheme: colorScheme,
                    onHelpLinkClicked: { resource in
                        if let linked = HelpTopic.topic(forResource: resource) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTopic = linked
                            }
                        }
                    }
                )
                .id(topic.id)
            }
            .transition(.opacity)
        } else {
            welcomeView
                .transition(.opacity)
        }
    }

    // MARK: - Welcome / Landing View

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Banner image
                if let bannerURL = Bundle.module.url(forResource: "header-banner", withExtension: "png") {
                    AsyncImage(url: bannerURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear.frame(height: 200)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(cardsAppeared ? 1 : 0)
                    .offset(y: cardsAppeared ? 0 : -6)
                    .animation(.easeOut(duration: 0.4), value: cardsAppeared)
                    .padding(.bottom, 28)
                }

                // Cards grouped by section
                VStack(spacing: 22) {
                    ForEach(HelpTopicGroup.allCases, id: \.self) { group in
                        let topics = HelpTopic.allTopics.filter { $0.group == group }
                        if !topics.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                // Section header
                                Text(group.rawValue)
                                    .font(.system(.subheadline, design: .serif))
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(nsColor: .init(red: 0.40, green: 0.32, blue: 0.24, alpha: 1.0)))

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                                    ForEach(topics) { topic in
                                        let globalIndex = HelpTopic.allTopics.firstIndex(of: topic) ?? 0
                                        topicCard(topic, number: globalIndex + 1)
                                            .opacity(cardsAppeared ? 1 : 0)
                                            .offset(y: cardsAppeared ? 0 : 8)
                                            .animation(
                                                .easeOut(duration: 0.3).delay(0.04 * Double(globalIndex)),
                                                value: cardsAppeared
                                            )
                                    }
                                }
                            }
                        }
                    }
                }

                // End-of-page flourish — same splotch style as article dividers
                if let flourishURL = Bundle.module.url(forResource: "decor-divider", withExtension: "png") {
                    Image(nsImage: NSImage(contentsOf: flourishURL) ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280)
                        .blendMode(.multiply)
                        .opacity(cardsAppeared ? 0.8 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: cardsAppeared)
                        .padding(.top, 40)
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .init(red: 0.98, green: 0.96, blue: 0.94, alpha: 1.0)))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                cardsAppeared = true
            }
        }
    }

    private func topicCard(_ topic: HelpTopic, number: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTopic = topic
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.title3)
                    .foregroundColor(Color(nsColor: .init(red: 0.55, green: 0.37, blue: 0.24, alpha: 1.0)))
                    .frame(width: 24, height: 24, alignment: .center)
                Text(topic.title)
                    .font(.system(.body, design: .serif))
                    .fontWeight(.medium)
                    .foregroundColor(Color(nsColor: .init(red: 0.29, green: 0.22, blue: 0.16, alpha: 1.0)))
                    .lineLimit(1)
                Spacer()
                // Number hint, vertically aligned with title
                if number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(nsColor: .init(red: 0.55, green: 0.45, blue: 0.35, alpha: 0.4)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .init(red: 0.55, green: 0.37, blue: 0.24, alpha: 0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(CardHoverStyle())
        .accessibilityIdentifier("help-topic-\(topic.id)")
    }
}

// MARK: - Card Hover Style (subtle shadow lift)

private struct CardHoverStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(isHovered ? 0.04 : 0))
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.10 : 0),
                radius: isHovered ? 8 : 0,
                y: isHovered ? 3 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Toolbar Button Style (back, prev/next arrows)

private struct ToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Home Button Hover Style

private struct HomeButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(isHovered ? 0.12 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

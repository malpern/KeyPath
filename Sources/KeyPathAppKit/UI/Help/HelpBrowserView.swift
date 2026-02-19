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
        HelpTopic(id: "concepts", title: "Keyboard Concepts", icon: "keyboard", resource: "concepts", group: .gettingStarted),
        HelpTopic(id: "use-cases", title: "What You Can Build", icon: "hammer", resource: "use-cases", group: .gettingStarted),
        // Features
        HelpTopic(id: "home-row-mods", title: "Home Row Mods", icon: "hand.raised", resource: "home-row-mods", group: .features),
        HelpTopic(id: "tap-hold", title: "Tap-Hold & Tap-Dance", icon: "hand.tap", resource: "tap-hold", group: .features),
        HelpTopic(id: "window-management", title: "Window Management", icon: "macwindow.on.rectangle", resource: "window-management", group: .features),
        HelpTopic(id: "action-uri", title: "Action URIs", icon: "link", resource: "action-uri", group: .features),
        // Reference
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
    @Environment(\.colorScheme) private var colorScheme

    /// Optional initial topic to select on appear.
    var initialTopic: HelpTopic?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear {
            if let initialTopic {
                selectedTopic = initialTopic
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTopic) {
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
        .safeAreaInset(edge: .bottom) {
            footerLinks
        }
        .frame(minWidth: 200)
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 12) {
            Link("KeyPath Website", destination: URL(string: "https://keypath-app.com/docs")!)
            Text("·")
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
            MarkdownWebView(
                resource: topic.resource,
                colorScheme: colorScheme,
                onHelpLinkClicked: { resource in
                    if let linked = HelpTopic.topic(forResource: resource) {
                        selectedTopic = linked
                    }
                }
            )
        } else {
            welcomeView
        }
    }

    // MARK: - Welcome / Landing View

    private var welcomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KeyPath Help")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Learn how to remap your keyboard, build powerful shortcuts, and customize your workflow.")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(HelpTopic.allTopics) { topic in
                        topicCard(topic)
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topicCard(_ topic: HelpTopic) -> some View {
        Button {
            selectedTopic = topic
        } label: {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .fontWeight(.medium)
                    Text(topic.group.rawValue)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

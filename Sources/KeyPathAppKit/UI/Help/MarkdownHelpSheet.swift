import SwiftUI
import WebKit

/// A reusable sheet that displays a help article from the KeyPath website.
struct MarkdownHelpSheet: View {
    let resource: String
    let title: String

    @State private var linkedResource: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(linkedResource.flatMap { HelpTopic.topic(forResource: $0)?.title } ?? title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown-help-close-button")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            WebHelpView(
                url: HelpTopic.topic(forResource: linkedResource ?? resource)?.webURL
                    ?? URL(string: "\(HelpTopic.baseURL)/guides/\(resource)/")
                    ?? URL(fileURLWithPath: "/"),
                onHelpLinkClicked: { linkedResource = $0 }
            )
        }
        .frame(width: 750, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

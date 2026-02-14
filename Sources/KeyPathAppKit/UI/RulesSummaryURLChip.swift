import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Displays a URL favicon + domain in keycap style for rules summary rows.
struct RulesSummaryURLChip: View {
    let urlString: String

    @State private var favicon: NSImage?

    private var domain: String {
        KeyMappingFormatter.extractDomain(from: urlString)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundColor(KeycapStyle.textColor.opacity(0.6))
                    .frame(width: 16, height: 16)
            }

            Text(domain)
                .font(.body.monospaced().weight(.semibold))
                .foregroundColor(KeycapStyle.textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .fill(Color.accentColor.opacity(0.2))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        )
        .onAppear {
            Task { @MainActor in
                favicon = await FaviconFetcher.shared.fetchFavicon(for: urlString)
            }
        }
    }
}

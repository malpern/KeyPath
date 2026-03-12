import AppKit
import KeyPathCore
import SwiftUI

// MARK: - URL Chip

/// Displays a favicon and domain in a chip style for URL actions
struct URLChip: View {
    let urlString: String

    @Environment(\.services) private var services
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
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }

            Text(domain)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .onAppear {
            Task { @MainActor in
                favicon = await services.faviconFetcher.fetchFavicon(for: urlString)
            }
        }
    }
}

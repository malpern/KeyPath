import SwiftUI

/// Default list view for the Context HUD showing keycap + action pairs grouped by collection
struct ContextHUDDefaultListView: View {
    let groups: [HUDKeyGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    // Collection header
                    if groups.count > 1 {
                        Text(group.name.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(group.color.opacity(0.8))
                            .tracking(1.5)
                    }

                    // Key entries in a flowing layout
                    FlowLayout(spacing: 4) {
                        ForEach(group.entries) { entry in
                            HUDKeycapChip(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

/// A compact keycap chip showing the key and its action
struct HUDKeycapChip: View {
    let entry: HUDKeyEntry

    var body: some View {
        HStack(spacing: 4) {
            // Keycap
            Text(entry.keycap)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(entry.color.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(entry.color.opacity(0.5), lineWidth: 0.5)
                )

            // Action label or SF Symbol
            if let sfSymbol = entry.sfSymbol {
                Image(systemName: sfSymbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text(entry.action)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 4)
    }
}

// FlowLayout is defined in InputCaptureExperiment.swift and reused here

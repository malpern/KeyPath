import SwiftUI

/// Default list view for the Context HUD showing keycap + action pairs in columns
struct ContextHUDDefaultListView: View {
    let groups: [HUDKeyGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    // Collection header
                    if groups.count > 1 {
                        Text(group.name.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(group.color.opacity(0.8))
                            .tracking(1.5)
                    }

                    // Key entries in columns (max 4 per column)
                    ColumnarKeyLayout(entries: group.entries)
                }
            }
        }
    }
}

/// Lays out key entries in columns with a maximum of 4 rows each
private struct ColumnarKeyLayout: View {
    let entries: [HUDKeyEntry]

    private let maxRowsPerColumn = 4

    private var columns: [[HUDKeyEntry]] {
        guard !entries.isEmpty else { return [] }
        let columnCount = (entries.count + maxRowsPerColumn - 1) / maxRowsPerColumn
        var result: [[HUDKeyEntry]] = []
        for col in 0 ..< columnCount {
            let start = col * maxRowsPerColumn
            let end = min(start + maxRowsPerColumn, entries.count)
            result.append(Array(entries[start ..< end]))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(column) { entry in
                        HUDKeycapChip(entry: entry)
                    }
                }
            }
        }
    }
}

/// A keycap chip showing the key and its action
struct HUDKeycapChip: View {
    let entry: HUDKeyEntry

    var body: some View {
        HStack(spacing: 10) {
            // Keycap
            Text(entry.keycap)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 32, minHeight: 32)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.color.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(entry.color.opacity(0.5), lineWidth: 0.5)
                )

            // Action label or SF Symbol
            if let sfSymbol = entry.sfSymbol {
                Image(systemName: sfSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text(entry.action)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }
}

// FlowLayout is defined in InputCaptureExperiment.swift and reused here

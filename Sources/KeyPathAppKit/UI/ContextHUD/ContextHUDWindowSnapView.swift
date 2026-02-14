import SwiftUI

/// Compact window snap zone grid for the Context HUD
/// Shows a simplified monitor with key labels positioned in snap zones
struct ContextHUDWindowSnapView: View {
    let entries: [HUDKeyEntry]

    private let gridColumns = 3
    private let gridRows = 3

    var body: some View {
        VStack(spacing: 6) {
            // Monitor frame
            ZStack {
                // Monitor background
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )

                // Snap zone grid
                snapZoneGrid
                    .padding(4)
            }
            .frame(height: 100)
            .accessibilityLabel("Window snap zones")

            // Unmapped keys listed below grid
            if !unmappedEntries.isEmpty {
                HStack(spacing: 6) {
                    ForEach(unmappedEntries) { entry in
                        HUDKeycapChip(entry: entry)
                    }
                }
            }
        }
    }

    private var snapZoneGrid: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0 ..< gridRows, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< gridColumns, id: \.self) { col in
                        snapZoneCell(row: row, col: col)
                    }
                }
            }
        }
    }

    private func snapZoneCell(row: Int, col: Int) -> some View {
        let entry = entryForZone(row: row, col: col)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(entry != nil ? Color.purple.opacity(0.25) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.purple.opacity(entry != nil ? 0.5 : 0.15), lineWidth: 0.5)
            )
            .overlay(
                Group {
                    if let entry {
                        Text(entry.keycap)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            )
    }

    /// Map snap zone position to key entry using Vim-style directional keys
    private func entryForZone(row: Int, col: Int) -> HUDKeyEntry? {
        // Try to match entries to grid positions based on their action labels
        let position = (row, col)
        for entry in entries {
            let action = entry.action.lowercased()
            switch position {
            case (0, 0) where action.contains("top") && action.contains("left"): return entry
            case (0, 1) where action.contains("top") && !action.contains("left") && !action.contains("right"): return entry
            case (0, 1) where action.contains("maximize") || action.contains("full"): return entry
            case (0, 2) where action.contains("top") && action.contains("right"): return entry
            case (1, 0) where action.contains("left") && !action.contains("top") && !action.contains("bottom"): return entry
            case (1, 1) where action.contains("center"): return entry
            case (1, 2) where action.contains("right") && !action.contains("top") && !action.contains("bottom"): return entry
            case (2, 0) where action.contains("bottom") && action.contains("left"): return entry
            case (2, 1) where action.contains("bottom") && !action.contains("left") && !action.contains("right"): return entry
            case (2, 2) where action.contains("bottom") && action.contains("right"): return entry
            default: continue
            }
        }
        return nil
    }

    /// Entries that couldn't be mapped to grid positions
    private var unmappedEntries: [HUDKeyEntry] {
        let gridEntries = Set((0 ..< gridRows).flatMap { row in
            (0 ..< gridColumns).compactMap { col in
                entryForZone(row: row, col: col)?.keyCode
            }
        })
        return entries.filter { !gridEntries.contains($0.keyCode) }
    }
}

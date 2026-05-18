import SwiftUI

#if os(macOS)
    import AppKit
#endif

enum KeyboardZone: Equatable {
    case modifier
    case activator
    case navMapping
    case dimmed
}

struct ZonedKeycap: View {
    let label: String
    let zone: KeyboardZone
    let subtitle: String?
    let size: CGFloat

    init(label: String, zone: KeyboardZone, subtitle: String? = nil, size: CGFloat = 22) {
        self.label = label
        self.zone = zone
        self.subtitle = subtitle
        self.size = size
    }

    private var fillColor: Color {
        switch zone {
        case .modifier: Color.blue.opacity(0.45)
        case .activator: Color.orange.opacity(0.5)
        case .navMapping: Color.green.opacity(0.45)
        case .dimmed: Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    private var borderColor: Color {
        switch zone {
        case .modifier: Color.blue.opacity(0.7)
        case .activator: Color.orange.opacity(0.8)
        case .navMapping: Color.green.opacity(0.7)
        case .dimmed: Color.secondary.opacity(0.1)
        }
    }

    private var textColor: Color {
        switch zone {
        case .dimmed: .secondary.opacity(0.25)
        default: .primary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: size * 0.5, weight: zone == .dimmed ? .regular : .semibold, design: .monospaced))
                .foregroundColor(textColor)
            if let subtitle {
                if NSImage(systemSymbolName: subtitle, accessibilityDescription: nil) != nil {
                    Image(systemName: subtitle)
                        .font(.system(size: size * 0.28, weight: .medium))
                        .foregroundColor(textColor.opacity(0.7))
                } else {
                    Text(subtitle)
                        .font(.system(size: size * 0.3, weight: .medium))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: size, height: subtitle != nil ? size * 1.2 : size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

struct ZonedKeyboardDiagram: View {
    let zones: [UInt16: KeyboardZone]
    let subtitles: [UInt16: String]
    let keycapSize: CGFloat
    let highlightOnly: Bool

    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId

    init(
        zones: [UInt16: KeyboardZone],
        subtitles: [UInt16: String] = [:],
        keycapSize: CGFloat = 26,
        highlightOnly: Bool = false
    ) {
        self.zones = zones
        self.subtitles = subtitles
        self.keycapSize = keycapSize
        self.highlightOnly = highlightOnly
    }

    private struct DisplayKey: Identifiable {
        let keyCode: UInt16
        let label: String
        let x: Double
        let y: Double
        var id: UInt16 { keyCode }
    }

    private var activeKeymap: LogicalKeymap {
        .resolve(id: selectedKeymapId)
    }

    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    private static let alphaKeys: Set<String> = [
        "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
        "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon",
        "z", "x", "c", "v", "b", "n", "m", "comma", "dot", "slash"
    ]

    private var keyboardRows: [[DisplayKey]] {
        let keys = activeLayout.keys.compactMap { key -> DisplayKey? in
            guard key.keyCode != PhysicalKey.unmappedKeyCode else { return nil }
            let canonical = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
            guard Self.alphaKeys.contains(canonical) else { return nil }
            if highlightOnly, zones[key.keyCode] == nil { return nil }
            let fallback: [String: String] = [
                "semicolon": ";", "comma": ",", "dot": ".", "slash": "/"
            ]
            let label = activeKeymap.label(for: key.keyCode, includeExtraKeys: false)
                ?? fallback[canonical] ?? canonical
            return DisplayKey(keyCode: key.keyCode, label: label, x: key.visualX, y: key.visualY)
        }

        let sorted = keys.sorted {
            if abs($0.y - $1.y) > 0.01 { return $0.y < $1.y }
            return $0.x < $1.x
        }

        var rows: [[DisplayKey]] = []
        var rowAnchors: [Double] = []
        for key in sorted {
            if let lastIndex = rowAnchors.indices.last, abs(key.y - rowAnchors[lastIndex]) <= 0.6 {
                rows[lastIndex].append(key)
            } else {
                rows.append([key])
                rowAnchors.append(key.y)
            }
        }
        return rows.map { $0.sorted { $0.x < $1.x } }.filter { !$0.isEmpty }
    }

    var body: some View {
        let rows = keyboardRows
        let globalMinX = rows.flatMap { $0 }.map(\.x).min() ?? 0
        let keyPitch = keycapSize + 3

        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let rowMinX = row.first?.x ?? globalMinX
                let indent = CGFloat(max(0, rowMinX - globalMinX)) * keyPitch

                HStack(spacing: 3) {
                    if indent > 0 {
                        Spacer().frame(width: indent)
                    }
                    ForEach(row) { key in
                        let zone = zones[key.keyCode] ?? .dimmed
                        ZonedKeycap(
                            label: key.label.count == 1 ? key.label.uppercased() : key.label,
                            zone: zone,
                            subtitle: subtitles[key.keyCode],
                            size: keycapSize
                        )
                    }
                }
            }
        }
    }
}

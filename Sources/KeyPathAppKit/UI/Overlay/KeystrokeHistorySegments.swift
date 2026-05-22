import AppKit
import SwiftUI

// MARK: - Text Run View

struct TextRunView: View {
    let segment: TextRunSegment
    let isDark: Bool
    @State private var hoveredCharId: UUID?
    @State private var activePopoverCharId: UUID?
    @State private var hoverTimer: Timer?

    private let hoverDelay: TimeInterval = 0.35

    var body: some View {
        FlowLayout(spacing: 0) {
            ForEach(segment.characters) { char in
                characterView(char)
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(activePopoverCharId != nil
                    ? Color.accentColor.opacity(0.06)
                    : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: activePopoverCharId)
    }

    private func characterView(_ char: TextRunCharacter) -> some View {
        Text(char.displayChar)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(isDark ? .white : .primary)
            .padding(.horizontal, 0.5)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(activePopoverCharId == char.id
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
            )
            .onHover { isHovering in
                if isHovering {
                    hoveredCharId = char.id
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { _ in
                        Task { @MainActor in
                            if hoveredCharId == char.id {
                                activePopoverCharId = char.id
                            }
                        }
                    }
                } else {
                    if hoveredCharId == char.id {
                        hoveredCharId = nil
                    }
                    hoverTimer?.invalidate()
                    hoverTimer = nil
                }
            }
            .popover(isPresented: Binding(
                get: { activePopoverCharId == char.id },
                set: { if !$0 {
                    activePopoverCharId = nil
                    hoveredCharId = nil
                } }
            )) {
                KeystrokeCharacterPopover(
                    char: char,
                    previousChar: previousChar(before: char)
                )
            }
    }

    private func previousChar(before char: TextRunCharacter) -> TextRunCharacter? {
        guard let index = segment.characters.firstIndex(where: { $0.id == char.id }),
              index > 0
        else { return nil }
        return segment.characters[index - 1]
    }
}

// MARK: - Event Card View

struct EventCardView: View {
    let segment: EventCardSegment
    let isDark: Bool

    var body: some View {
        Group {
            switch segment.cardKind {
            case let .tapHold(data):
                tapHoldCard(data)
            case let .hrmDecision(data):
                hrmCard(data)
            case let .oneShot(data):
                oneShotCard(data)
            case let .chord(data):
                chordCard(data)
            case let .tapDance(data):
                tapDanceCard(data)
            case let .nonPrintableKeys(keys):
                nonPrintableCard(keys: keys)
            case let .actionDispatched(data):
                actionDispatchedCard(data)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tap-Hold Card

    private func tapHoldCard(_ data: TapHoldCardData) -> some View {
        HStack(spacing: 4) {
            Text(data.isHold ? "HOLD" : "TAP")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(data.isHold ? Color.orange : Color.blue)
                )

            Text(data.key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            Text(data.outputAction)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)

            if let reason = data.reason {
                reasonPill(reason)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackground(for: data.isHold ? .orange : .blue))
        )
    }

    // MARK: - HRM Decision Card

    private func hrmCard(_ data: HrmCardData) -> some View {
        HStack(spacing: 4) {
            let isHold = data.decision == .hold

            if data.isNearThreshold {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }

            Text(isHold ? "HOLD" : "TAP")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isHold ? Color.orange : Color.blue)
                )

            Text(data.key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)

            reasonPill(data.reason.displayName)

            if let latency = data.decideLatencyMs {
                latencyBadge(latency: latency, threshold: data.configuredThresholdMs)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(data.isNearThreshold
                    ? cardBackground(for: .yellow)
                    : cardBackground(for: data.decision == .hold ? .orange : .blue))
        )
    }

    // MARK: - One-Shot Card

    private func oneShotCard(_ data: OneShotPayload) -> some View {
        HStack(spacing: 4) {
            Text("OS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.purple)
                )

            Text(data.modifiers)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackground(for: .purple))
        )
    }

    // MARK: - Chord Card

    private func chordCard(_ data: ChordPayload) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pianokeys")
                .font(.system(size: 9))
                .foregroundStyle(.green)

            Text(data.keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            Text(data.action)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackground(for: .green))
        )
    }

    // MARK: - Tap-Dance Card

    private func tapDanceCard(_ data: TapDancePayload) -> some View {
        HStack(spacing: 4) {
            Text(data.key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("\u{00D7}\(data.tapCount)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.teal)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            Text(data.action)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackground(for: .teal))
        )
    }

    // MARK: - Action Dispatched Card

    private func actionDispatchedCard(_ data: ActionDispatchedPayload) -> some View {
        HStack(spacing: 4) {
            let icon = actionIcon(for: data.action)
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.mint)

            Text(data.action.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.mint)
                )

            if let target = data.target, !target.isEmpty {
                Text(target.localizedCapitalized)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isDark ? .white : .primary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(cardBackground(for: .mint))
        )
    }

    private func actionIcon(for action: String) -> String {
        switch action {
        case "launch": "arrow.up.forward.app"
        case "open": "link"
        case "notify": "bell"
        default: "bolt"
        }
    }

    // MARK: - Non-Printable Key Card

    private func nonPrintableCard(keys: [(key: String, count: Int)]) -> some View {
        FlowLayout(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 1) {
                    Text(TimelineGrouper.nonPrintableDisplayNames[entry.key.lowercased()] ?? entry.key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if entry.count > 1 {
                        Text("\u{00D7}\(entry.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isDark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.04))
        )
    }

    // MARK: - Shared Components

    private func reasonPill(_ reason: String) -> some View {
        Text(reason)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(isDark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06))
            )
    }

    private func latencyBadge(latency: Int, threshold: Int?) -> some View {
        let color = latencyColor(latency: latency, threshold: threshold)
        return Text("\(latency)ms")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
    }

    private func latencyColor(latency: Int, threshold: Int?) -> Color {
        guard let threshold, threshold > 0 else { return .secondary }
        let ratio = Double(latency) / Double(threshold)
        if ratio < 0.5 { return .green }
        if ratio < 0.8 { return .yellow }
        return .red
    }

    private func cardBackground(for tint: Color) -> Color {
        tint.opacity(isDark ? 0.1 : 0.06)
    }
}

// MARK: - Layer Divider View

struct LayerDividerView: View {
    let segment: LayerDividerSegment

    var body: some View {
        HStack(spacing: 6) {
            line
            Text(segment.layerName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            line
        }
        .padding(.vertical, 4)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 0.5)
    }
}

// MARK: - App Changed View

struct AppChangedView: View {
    let segment: AppChangedSegment

    var body: some View {
        HStack(spacing: 6) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(segment.appName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: segment.bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

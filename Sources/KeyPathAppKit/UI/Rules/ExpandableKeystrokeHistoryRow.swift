import AppKit
import SwiftUI

struct ExpandableKeystrokeHistoryRow: View {
    let isPackEnabled: Bool
    let onToggle: (Bool) -> Void
    var onTapRow: (() -> Void)?

    @State private var isHovered = false
    @State private var showConsentDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5)
                    : Color(NSColor.windowBackgroundColor))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .sheet(isPresented: $showConsentDialog) {
            KeystrokeHistoryConsentDialog(
                onConfirm: {
                    showConsentDialog = false
                    onToggle(true)
                },
                onCancel: {
                    showConsentDialog = false
                }
            )
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let onTapRow {
                    onTapRow()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: PackRegistry.keystrokeHistory.iconSymbol)
                        .font(.system(size: 14 * 0.85, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(width: 24 * 0.85, height: 24 * 0.85)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(PackRegistry.keystrokeHistory.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(PackRegistry.keystrokeHistory.tagline)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text("Memory only")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keystroke-history-row-label")

            Spacer()

            Toggle("", isOn: Binding(
                get: { isPackEnabled },
                set: { newValue in
                    if newValue {
                        showConsentDialog = true
                    } else {
                        onToggle(false)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .padding(.top, 6)
            .padding(.trailing, 8)
            .accessibilityIdentifier("keystroke-history-row-toggle")
            .accessibilityLabel("Enable Keystroke History")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

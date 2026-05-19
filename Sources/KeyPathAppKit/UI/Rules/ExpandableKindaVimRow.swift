import AppKit
import SwiftUI

struct ExpandableKindaVimRow: View {
    let isPackEnabled: Bool
    let onToggle: (Bool) -> Void
    var onTapRow: (() -> Void)?

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var appInstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .onAppear {
            appInstalled = FileManager.default.fileExists(atPath: "/Applications/kindaVim.app")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let onTapRow {
                    onTapRow()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: PackRegistry.kindaVim.iconSymbol)
                        .font(.system(size: 14 * 0.85, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(width: 24 * 0.85, height: 24 * 0.85)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(PackRegistry.kindaVim.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(PackRegistry.kindaVim.tagline)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules-kindavim-expand-button")

            Toggle("", isOn: Binding(
                get: { isPackEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(.blue)
            .labelsHidden()
            .accessibilityIdentifier("rules-kindavim-toggle")
            .accessibilityLabel("Toggle KindaVim")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        InsetBackPlane {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    staticModeBadge("NORMAL", tint: .green)
                    staticModeBadge("INSERT", tint: .blue)
                    staticModeBadge("VISUAL", tint: .orange)
                }

                HStack(spacing: 0) {
                    Text("Shows your current Vim mode in the overlay header. Requires ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("kindaVim.app ↗") {
                        if let url = URL(string: "https://kindavim.app") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }

                if !appInstalled {
                    Button {
                        if let url = URL(string: "https://kindavim.app") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Get KindaVim", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("kindavim-row-get-app")
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Static Mode Badge

    @ViewBuilder
    private func staticModeBadge(_ label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("VIM")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.15))
        )
    }
}

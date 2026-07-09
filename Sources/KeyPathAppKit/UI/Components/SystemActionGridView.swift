import KeyPathRulesCore
import SwiftUI

struct SystemActionGridView: View {
    let groups: [OutputActionGroup]
    let selectedActionID: String?
    let style: Style
    let onSelect: (SystemActionInfo) -> Void

    enum Style {
        case iconTile
        case labelPill(minWidth: CGFloat = 90)
    }

    var body: some View {
        switch style {
        case .iconTile:
            iconTileContent
        case let .labelPill(minWidth):
            labelPillContent(minWidth: minWidth)
        }
    }

    // MARK: - Icon Tile Style (Overlay Mapper)

    private var iconTileContent: some View {
        VStack(spacing: 0) {
            ForEach(groups) { group in
                HStack {
                    Text(group.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(group.actions) { action in
                        iconTileButton(action)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func iconTileButton(_ action: SystemActionInfo) -> some View {
        let isSelected = selectedActionID == action.id
        Button {
            onSelect(action)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: action.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                Text(action.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityIdentifier("system-action-\(action.id)")
    }

    // MARK: - Label Pill Style (Chord Editor)

    private func labelPillContent(minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups) { group in
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth))], spacing: 4) {
                    ForEach(group.actions) { action in
                        labelPillButton(action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func labelPillButton(_ action: SystemActionInfo) -> some View {
        let isSelected = selectedActionID == action.id
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: action.sfSymbol)
                    .font(.caption2)
                Text(action.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("system-action-\(action.id)")
    }
}

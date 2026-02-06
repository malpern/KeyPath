import SwiftUI

extension OverlayMapperSection {
    // MARK: - Output Type Dropdown

    var outputTypeDropdown: some View {
        let currentType = outputTypeDisplayInfo

        return Button {
            isSystemActionPickerOpen = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentType.icon)
                    .font(.system(size: 10))
                Text(currentType.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(currentType.isDefault ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(currentType.isDefault ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(currentType.isDefault ? Color.primary.opacity(0.2) : Color.accentColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-output-type")
        .accessibilityLabel("Select output action type")
        .popover(isPresented: $isSystemActionPickerOpen, arrowEdge: .bottom) {
            systemActionPopover
        }
    }

    /// Info about current output type for display
    private var outputTypeDisplayInfo: (label: String, icon: String, isDefault: Bool) {
        if viewModel.selectedApp != nil {
            ("Launch App", "app.fill", false)
        } else if viewModel.selectedSystemAction != nil {
            (viewModel.selectedSystemAction?.name ?? "System", "gearshape", false)
        } else if viewModel.selectedURL != nil {
            ("Open URL", "link", false)
        } else if selectedLayerOutput != nil {
            ("Go to Layer", "square.stack.3d.up", false)
        } else {
            ("Keystroke", "keyboard", true)
        }
    }
}

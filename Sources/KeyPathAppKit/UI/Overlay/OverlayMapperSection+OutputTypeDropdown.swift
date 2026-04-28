import SwiftUI

extension OverlayMapperSection {
    // MARK: - Output Type Dropdown

    var outputTypeDropdown: some View {
        let currentType = outputTypeDisplayInfo

        return HoverDropdownButton(
            text: currentType.label,
            sfSymbol: currentType.icon,
            action: { isSystemActionPickerOpen = true }
        )
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
        } else if viewModel.hasShiftedOutputConfigured {
            ("Keystroke + ⇧", "keyboard", false)
        } else {
            ("Keystroke", "keyboard", true)
        }
    }
}

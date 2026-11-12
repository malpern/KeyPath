import SwiftUI

extension OverlayMapperSection {
    // MARK: - Output Type Dropdown

    var outputTypeDropdown: some View {
        let currentType = outputTypeDisplayInfo

        return HoverDropdownButton(
            text: currentType.label,
            sfSymbol: currentType.icon,
            accessibilityIdentifier: "overlay-mapper-output-type",
            action: { isSystemActionPickerOpen = true }
        )
        .accessibilityLabel("Select output action type")
        .windowAnchoredPopover(isPresented: $isSystemActionPickerOpen) {
            systemActionPopover
        }
    }

    /// Info about current output type for display
    private var outputTypeDisplayInfo: (label: String, icon: String, isDefault: Bool) {
        if viewModel.selectedApp != nil {
            (String(localized: "Launch App"), "app.fill", false)
        } else if viewModel.selectedSystemAction != nil {
            (viewModel.selectedSystemAction?.name ?? String(localized: "System"), "gearshape", false)
        } else if viewModel.selectedURL != nil {
            (String(localized: "Open URL"), "link", false)
        } else if viewModel.selectedFolder != nil {
            (String(localized: "Open Folder"), "folder.fill", false)
        } else if viewModel.selectedScript != nil {
            (String(localized: "Run Script"), "terminal.fill", false)
        } else if viewModel.selectedLayerOutput != nil {
            (String(localized: "Go to Layer"), "square.stack.3d.up", false)
        } else if viewModel.hasShiftedOutputConfigured {
            (String(localized: "Keystroke + ⇧"), "keyboard", false)
        } else {
            (String(localized: "Keystroke"), "keyboard", true)
        }
    }
}

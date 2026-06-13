import AppKit
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Output-Type Picker (drill-down)

    /// Fixed popover size. A stable frame is the whole point of the drill-down:
    /// the picker swaps pages instead of growing in place, so the hoisted
    /// window-anchored layer never has to re-measure or reposition mid-interaction
    /// (which is what left the old inline-expand rows unresponsive).
    private var outputPickerWidth: CGFloat {
        280
    }

    private var outputPickerHeight: CGFloat {
        340
    }

    /// Output-type picker. An iPhone-style drill-down: the root page lists the
    /// output types; the three with sub-choices (System Action, Launch App, Go
    /// to Layer) slide over to their own page rather than expanding in place.
    var systemActionPopover: some View {
        ZStack(alignment: .top) {
            switch viewModel.outputPickerPage {
            case .root:
                outputPickerRootPage
                    .transition(.move(edge: .leading))
            case .systemActions:
                outputPickerSubPage(title: "System Action") {
                    SystemActionGridView(
                        groups: OutputActionGrouping.detailed,
                        selectedActionID: viewModel.selectedSystemAction?.id,
                        style: .iconTile,
                        onSelect: { action in
                            viewModel.selectSystemAction(action)
                            isSystemActionPickerOpen = false
                        }
                    )
                }
                .transition(.move(edge: .trailing))
            case .launchApps:
                outputPickerSubPage(title: "Launch App") {
                    launchAppsExpandedContent
                }
                .transition(.move(edge: .trailing))
            case .layers:
                outputPickerSubPage(title: "Go to Layer") {
                    layersExpandedContent
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(width: outputPickerWidth, height: outputPickerHeight, alignment: .top)
        .pickerPopoverChrome()
        .onAppear {
            // Always open at the root list; the selected type is shown with a
            // checkmark there, and a predictable entry point avoids surprising
            // the user with a deep page on reopen.
            viewModel.outputPickerPage = .root
            viewModel.launchAppSearchText = ""
        }
        .sheet(isPresented: $showingNewLayerDialog) {
            newLayerDialogContent
        }
    }

    // MARK: - Root Page

    private var outputPickerRootPage: some View {
        let isKeystrokeSelected = viewModel.selectedSystemAction == nil
            && viewModel.selectedApp == nil
            && viewModel.selectedLayerOutput == nil
            && viewModel.selectedURL == nil
            && viewModel.selectedFolder == nil
            && viewModel.selectedScript == nil

        return ScrollView {
            VStack(spacing: 0) {
                outputTypeLeafRow(
                    title: "Keystroke",
                    icon: "keyboard",
                    isSelected: isKeystrokeSelected,
                    accessibilityID: "overlay-mapper-output-keystroke"
                ) {
                    viewModel.selectedLayerOutput = nil
                    viewModel.revertToKeystroke()
                    isSystemActionPickerOpen = false
                }

                PopoverListDivider()

                outputTypeNavRow(
                    title: "System Action",
                    icon: "gearshape",
                    isSelected: viewModel.selectedSystemAction != nil,
                    detail: viewModel.selectedSystemAction?.name,
                    accessibilityID: "overlay-mapper-output-system-action"
                ) {
                    viewModel.outputPickerPage = .systemActions
                }

                PopoverListDivider()

                outputTypeNavRow(
                    title: "Launch App",
                    icon: "app.fill",
                    customIcon: viewModel.selectedApp?.icon,
                    isSelected: viewModel.selectedApp != nil,
                    detail: viewModel.selectedApp?.name,
                    accessibilityID: "overlay-mapper-output-launch-app"
                ) {
                    loadKnownApps()
                    viewModel.outputPickerPage = .launchApps
                }

                PopoverListDivider()

                outputTypeLeafRow(
                    title: "Open URL",
                    icon: "link",
                    isSelected: viewModel.selectedURL != nil,
                    detail: viewModel.selectedURL.map { KeyMappingFormatter.extractDomain(from: $0) },
                    accessibilityID: "overlay-mapper-output-url"
                ) {
                    isSystemActionPickerOpen = false
                    viewModel.showURLInputDialog()
                }

                PopoverListDivider()

                outputTypeLeafRow(
                    title: "Open Folder",
                    icon: "folder.fill",
                    isSelected: viewModel.selectedFolder != nil,
                    detail: viewModel.selectedFolder.map { $0.name ?? URL(fileURLWithPath: $0.path).lastPathComponent },
                    accessibilityID: "overlay-mapper-output-folder"
                ) {
                    isSystemActionPickerOpen = false
                    browseForFolder()
                }

                PopoverListDivider()

                outputTypeLeafRow(
                    title: "Run Script",
                    icon: "terminal.fill",
                    isSelected: viewModel.selectedScript != nil,
                    detail: viewModel.selectedScript.map { $0.name ?? URL(fileURLWithPath: $0.path).lastPathComponent },
                    accessibilityID: "overlay-mapper-output-script"
                ) {
                    isSystemActionPickerOpen = false
                    browseForScript()
                }

                PopoverListDivider()

                outputTypeNavRow(
                    title: "Go to Layer",
                    icon: "square.stack.3d.up",
                    isSelected: viewModel.selectedLayerOutput != nil,
                    detail: viewModel.selectedLayerOutput?.capitalized,
                    accessibilityID: "overlay-mapper-output-go-to-layer"
                ) {
                    Task { await viewModel.refreshAvailableLayers() }
                    viewModel.outputPickerPage = .layers
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Sub-Page Scaffold

    /// A sub-page: a back header that returns to the root list, then the
    /// category's content. The content reuses the same leaf-row lists the
    /// inline version used (`launchAppsExpandedContent`, `layersExpandedContent`,
    /// `SystemActionGridView`); each row selects and closes the popover.
    private func outputPickerSubPage(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    viewModel.outputPickerPage = .root
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                    Text(title)
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("overlay-mapper-output-back")

            PopoverListDivider()

            ScrollView {
                content()
                    .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Row Builders

    /// A terminal output type: selecting it applies the output and closes the
    /// popover (Keystroke, Open URL, Open Folder, Run Script).
    private func outputTypeLeafRow(
        title: String,
        icon: String,
        isSelected: Bool,
        detail: String? = nil,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier(accessibilityID)
    }

    /// An output type with sub-choices: tapping it drills into a sub-page.
    /// The trailing chevron points right to signal navigation.
    private func outputTypeNavRow(
        title: String,
        icon: String,
        customIcon: NSImage? = nil,
        isSelected: Bool,
        detail: String? = nil,
        accessibilityID: String,
        navigate: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                navigate()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)
                if let customIcon {
                    Image(nsImage: customIcon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .font(.body)
                        .frame(width: 20)
                }
                Text(title)
                    .font(.body)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Folder / Script Pickers

    /// Browse for a folder using NSOpenPanel
    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to open"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path: String = if url.path.hasPrefix(NSHomeDirectory()) {
            url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            url.path
        }

        viewModel.selectFolder(path: path, name: url.lastPathComponent)
    }

    /// Browse for a script file using NSOpenPanel
    private func browseForScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a script file"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.shellScript, .unixExecutable]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path: String = if url.path.hasPrefix(NSHomeDirectory()) {
            url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            url.path
        }

        let name = url.deletingPathExtension().lastPathComponent
        viewModel.selectScript(path: path, name: name)
    }
}

import AppKit
import SwiftUI

private struct SystemActionPopoverContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension OverlayMapperSection {
    // MARK: - System Action Groups

    /// System actions grouped for the popover
    struct SystemActionGroup {
        let title: String
        let actions: [SystemActionInfo]
    }

    private var systemActionGroups: [SystemActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            SystemActionGroup(title: "System", actions: all.filter {
                ["spotlight", "mission-control", "launchpad", "dnd", "notification-center", "dictation", "siri"].contains($0.id)
            }),
            SystemActionGroup(title: "Playback", actions: all.filter {
                ["play-pause", "next-track", "prev-track"].contains($0.id)
            }),
            SystemActionGroup(title: "Volume", actions: all.filter {
                ["mute", "volume-up", "volume-down"].contains($0.id)
            }),
            SystemActionGroup(title: "Display", actions: all.filter {
                ["brightness-up", "brightness-down"].contains($0.id)
            })
        ]
    }

    /// Keep the picker compact by default, then grow it to a larger scrollable surface
    /// whenever any section expands. Using an explicit height lets the popover resize
    /// with the presented SwiftUI view instead of relying on a maxHeight that never
    /// increases the popover's ideal size.
    private var collapsedPopoverHeight: CGFloat {
        270
    }

    private var hasExpandedSection: Bool {
        isSystemActionsExpanded || isLaunchAppsExpanded || isLayersExpanded
    }

    private var maximumPopoverHeight: CGFloat {
        let visibleScreenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(collapsedPopoverHeight * 2, max(collapsedPopoverHeight, visibleScreenHeight - 160))
    }

    private var popoverHeight: CGFloat {
        guard hasExpandedSection else { return collapsedPopoverHeight }
        let measuredHeight = max(collapsedPopoverHeight, outputActionPopoverContentHeight)
        return min(measuredHeight, maximumPopoverHeight)
    }

    /// Popover content for output type picker with collapsible sections
    var systemActionPopover: some View {
        let isKeystrokeSelected = viewModel.selectedSystemAction == nil && viewModel.selectedApp == nil && selectedLayerOutput == nil
        let isSystemActionSelected = viewModel.selectedSystemAction != nil
        let isAppSelected = viewModel.selectedApp != nil
        let isLayerSelected = selectedLayerOutput != nil
        let isURLSelected = viewModel.selectedURL != nil

        return ScrollView {
            VStack(spacing: 0) {
                // "Keystroke" option
                Button {
                    collapseAllSections()
                    selectedLayerOutput = nil
                    viewModel.revertToKeystroke()
                    isSystemActionPickerOpen = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isKeystrokeSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isKeystrokeSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "keyboard")
                            .font(.body)
                            .frame(width: 20)
                        Text("Keystroke")
                            .font(.body)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)

                PopoverListDivider()

                // "System Action" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isSystemActionsExpanded {
                            isLaunchAppsExpanded = false
                            isLayersExpanded = false
                        }
                        isSystemActionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSystemActionSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSystemActionSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "gearshape")
                            .font(.body)
                            .frame(width: 20)
                        Text("System Action")
                            .font(.body)
                        Spacer()
                        if let action = viewModel.selectedSystemAction {
                            Text(action.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isSystemActionsExpanded ? "chevron.up" : "chevron.down")
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

                // Collapsible system actions grid
                if isSystemActionsExpanded {
                    VStack(spacing: 0) {
                        ForEach(systemActionGroups, id: \.title) { group in
                            systemActionGroupView(group)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PopoverListDivider()

                // "Launch App" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isLaunchAppsExpanded {
                            isSystemActionsExpanded = false
                            isLayersExpanded = false
                        }
                        isLaunchAppsExpanded.toggle()
                        if isLaunchAppsExpanded {
                            loadKnownApps()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isAppSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isAppSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        if let app = viewModel.selectedApp {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.body)
                                .frame(width: 20)
                        }
                        Text(viewModel.selectedApp?.name ?? "Launch App")
                            .font(.body)
                        Spacer()
                        if let app = viewModel.selectedApp {
                            Text(app.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isLaunchAppsExpanded ? "chevron.up" : "chevron.down")
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

                // Collapsible known apps list
                if isLaunchAppsExpanded {
                    launchAppsExpandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PopoverListDivider()

                // "Open URL" option
                Button {
                    collapseAllSections()
                    isSystemActionPickerOpen = false
                    viewModel.showURLInputDialog()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isURLSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isURLSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "link")
                            .font(.body)
                            .frame(width: 20)
                        Text("Open URL")
                            .font(.body)
                        Spacer()
                        if let url = viewModel.selectedURL {
                            Text(KeyMappingFormatter.extractDomain(from: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)
                .accessibilityIdentifier("overlay-mapper-output-url")

                PopoverListDivider()

                // "Go to Layer" option - clickable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isLayersExpanded {
                            isSystemActionsExpanded = false
                            isLaunchAppsExpanded = false
                        }
                        isLayersExpanded.toggle()
                        if isLayersExpanded {
                            Task { await viewModel.refreshAvailableLayers() }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isLayerSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isLayerSelected ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Image(systemName: "square.stack.3d.up")
                            .font(.body)
                            .frame(width: 20)
                        Text("Go to Layer")
                            .font(.body)
                        Spacer()
                        if let layer = selectedLayerOutput {
                            Text(layer.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isLayersExpanded ? "chevron.up" : "chevron.down")
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

                // Collapsible layers list
                if isLayersExpanded {
                    layersExpandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 6)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SystemActionPopoverContentHeightKey.self,
                        value: geometry.size.height
                    )
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 320, height: popoverHeight, alignment: .top)
        .pickerPopoverChrome()
        .animation(.easeInOut(duration: 0.25), value: popoverHeight)
        .animation(.easeInOut(duration: 0.25), value: isSystemActionsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLaunchAppsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLayersExpanded)
        .onPreferenceChange(SystemActionPopoverContentHeightKey.self) { measuredHeight in
            let snappedHeight = ceil(measuredHeight)
            guard abs(outputActionPopoverContentHeight - snappedHeight) > 1 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                outputActionPopoverContentHeight = snappedHeight
            }
        }
        .onAppear {
            // Auto-expand the relevant section based on current selection
            isSystemActionsExpanded = viewModel.selectedSystemAction != nil
            isLaunchAppsExpanded = viewModel.selectedApp != nil
            isLayersExpanded = selectedLayerOutput != nil
            outputActionPopoverContentHeight = collapsedPopoverHeight
            if isLaunchAppsExpanded {
                loadKnownApps()
            }
        }
        .sheet(isPresented: $showingNewLayerDialog) {
            newLayerDialogContent
        }
    }

    /// Collapse all expandable sections
    private func collapseAllSections() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSystemActionsExpanded = false
            isLaunchAppsExpanded = false
            isLayersExpanded = false
        }
    }
}

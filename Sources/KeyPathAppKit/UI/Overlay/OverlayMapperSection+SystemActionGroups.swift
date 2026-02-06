import SwiftUI

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

    /// Dynamic max height for the popover based on expansion state
    private var expandedMaxHeight: CGFloat {
        let baseHeight: CGFloat = 270 // Height for collapsed state (5 rows + dividers)
        let systemActionsHeight: CGFloat = 480 // System actions grid when expanded
        let appsHeight: CGFloat = 300 // Apps list when expanded
        let layersHeight: CGFloat = 250 // Layers list when expanded

        var height = baseHeight
        if isSystemActionsExpanded { height += systemActionsHeight }
        if isLaunchAppsExpanded { height += appsHeight }
        if isLayersExpanded { height += layersHeight }

        return min(height, 750) // Cap at reasonable screen height
    }

    private var popoverMaxHeight: CGFloat {
        if isSystemActionsExpanded {
            return min(expandedMaxHeight * 2, 1000)
        }
        return expandedMaxHeight
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

                Divider().opacity(0.2).padding(.horizontal, 8)

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

                Divider().opacity(0.2).padding(.horizontal, 8)

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

                Divider().opacity(0.2).padding(.horizontal, 8)

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

                Divider().opacity(0.2).padding(.horizontal, 8)

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
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 320)
        .frame(maxHeight: popoverMaxHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: isSystemActionsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLaunchAppsExpanded)
        .animation(.easeInOut(duration: 0.25), value: isLayersExpanded)
        .padding(4)
        .onAppear {
            // Auto-expand the relevant section based on current selection
            isSystemActionsExpanded = viewModel.selectedSystemAction != nil
            isLaunchAppsExpanded = viewModel.selectedApp != nil
            isLayersExpanded = selectedLayerOutput != nil
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

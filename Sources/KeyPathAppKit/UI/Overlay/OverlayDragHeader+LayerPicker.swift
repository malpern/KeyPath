import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Layer Picker Popover Content

extension OverlayDragHeader {
    /// Popover showing available layers
    var layerPickerPopover: some View {
        VStack(spacing: 0) {
            if !connectedKeyboards.isEmpty {
                keyboardPickerSection
                PopoverListDivider()
            }

            layerPickerSectionHeader

            ForEach(availableLayers.indices, id: \.self) { index in
                let layer = availableLayers[index]
                layerPickerRow(layer: layer, index: index)

                if index < availableLayers.count - 1 {
                    PopoverListDivider()
                }
            }

            PopoverListDivider()

            // New Layer option - styled same as layer rows
            Button {
                isLayerPickerOpen = false
                showingNewLayerSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("layer-picker-new")
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .pickerPopoverChrome()
    }

    var keyboardPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connected Keyboards")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            ForEach(connectedKeyboards) { keyboard in
                keyboardPickerRow(keyboard)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    var layerPickerSectionHeader: some View {
        Text("Layers")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, connectedKeyboards.isEmpty ? 2 : 6)
            .padding(.bottom, 6)
    }

    func keyboardPickerRow(_ keyboard: AutoDetectKeyboardController.ConnectedKeyboard) -> some View {
        let isCurrentKeyboard = activeKeyboardID == keyboard.id
        let accessibilityID = "keyboard-picker-\(keyboard.vidPidKey.replacingOccurrences(of: ":", with: "-"))"

        return Button {
            isLayerPickerOpen = false
            onKeyboardSelected(keyboard.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.body)
                    .frame(width: 20)
                    .foregroundStyle(isCurrentKeyboard ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(keyboard.keyboardName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(keyboard.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isCurrentKeyboard {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else if keyboard.status == .importRequired {
                    Text("Import")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if keyboard.status == .possibleMatch {
                    Text("Review")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if keyboard.status == .unrecognized {
                    Text("Search")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerButtonStyle())
        .focusable(false)
        .accessibilityIdentifier(accessibilityID)
    }

    /// Individual layer row in the picker
    @ViewBuilder
    func layerPickerRow(layer: String, index _: Int) -> some View {
        let displayName = LayerInfo.displayName(for: layer)
        let isCurrentLayer = currentLayerName.lowercased() == layer.lowercased()
        let layerIcon = LayerInfo.iconName(for: layer)
        let canDelete = !isSystemLayer(layer)
        let isHovered = hoveredLayer == layer

        HStack(spacing: 0) {
            Button {
                isLayerPickerOpen = false
                onLayerSelected(layer)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: layerIcon)
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(isCurrentLayer ? Color.accentColor : .secondary)
                    Text(displayName)
                        .font(.body)
                    Spacer()
                    if isCurrentLayer {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("layer-picker-\(layer)")

            // Delete button for user-created layers (hover only)
            if canDelete {
                Button {
                    isLayerPickerOpen = false
                    onDeleteLayer?(layer)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .opacity(isHovered ? 1 : 0)
                .accessibilityIdentifier("layer-delete-\(layer)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isCurrentLayer ? 0.05 : (isHovered ? 0.03 : 0)))
        )
        .accessibilityIdentifier("layer-picker-row-\(layer)")
        .accessibilityLabel("\(displayName) layer")
        .accessibilityValue(isCurrentLayer ? "selected" : (canDelete ? "custom" : "system"))
        .accessibilityHint(canDelete ? "Use Select or Delete actions to manage this layer." : "Use Select to switch to this layer.")
        .accessibilityAction(named: "Select") {
            isLayerPickerOpen = false
            onLayerSelected(layer)
        }
        .modifier(
            LayerPickerDeleteAccessibilityAction(
                layer: layer,
                canDelete: canDelete,
                closePicker: { isLayerPickerOpen = false },
                onDeleteLayer: onDeleteLayer
            )
        )
        .onHover { hovering in
            hoveredLayer = hovering ? layer : nil
        }
    }

    struct LayerPickerDeleteAccessibilityAction: ViewModifier {
        let layer: String
        let canDelete: Bool
        let closePicker: () -> Void
        let onDeleteLayer: ((String) -> Void)?

        func body(content: Content) -> some View {
            if canDelete {
                content
                    .accessibilityAction(named: "Delete") {
                        closePicker()
                        onDeleteLayer?(layer)
                    }
            } else {
                content
            }
        }
    }

    /// Button style for layer picker items (no focus ring)
    struct LayerPickerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
                )
        }
    }

    func kanataDisconnectedPill(indicatorCornerRadius: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.caption2.weight(.medium))
            Text("No TCP")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.orange.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: indicatorCornerRadius)
                .fill(Color.orange.opacity(isDark ? 0.15 : 0.2))
        )
        .help("Not receiving events from Kanata")
        .accessibilityIdentifier("overlay-kanata-disconnected-indicator")
        .accessibilityLabel("Not connected to Kanata TCP server")
    }
}

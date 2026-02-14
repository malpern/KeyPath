import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Compact row for displaying an app-specific rule override
struct AppRuleRowCompact: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onEdit: () -> Void
    let onDelete: () -> Void
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: override.outputAction)
    }

    private var systemActionIdentifier: String? {
        if let extracted = KeyboardVisualizationViewModel.extractSystemActionIdentifier(from: override.outputAction) {
            return extracted
        }
        return SystemActionInfo.find(byOutput: override.outputAction)?.id
    }

    private var urlIdentifier: String? {
        KeyboardVisualizationViewModel.extractUrlIdentifier(from: override.outputAction)
    }

    private var layerSwitchIdentifier: String? {
        LayerInfo.extractLayerName(from: override.outputAction)
    }

    var body: some View {
        Button(action: { onEdit() }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Mapping content
                    HStack(spacing: 8) {
                        // Input key
                        Text(prettyKeyName(override.inputKey))
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(KeycapStyle.textColor)
                            .modifier(KeycapStyle())

                        Image(systemName: "arrow.right")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)

                        // Output action chip
                        if let appId = appLaunchIdentifier {
                            RulesSummaryAppLaunchChip(appIdentifier: appId)
                        } else if let actionId = systemActionIdentifier {
                            RulesSummarySystemActionChip(actionIdentifier: actionId)
                        } else if let urlId = urlIdentifier {
                            RulesSummaryURLChip(urlString: urlId)
                        } else if let layerName = layerSwitchIdentifier {
                            RulesSummaryLayerSwitchChip(layerName: layerName)
                        } else {
                            Text(prettyKeyName(override.outputAction))
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(KeycapStyle.textColor)
                                .modifier(KeycapStyle())
                        }

                        Spacer(minLength: 0)
                    }

                    Spacer()

                    // Action buttons - subtle icons that appear on hover (matching MappingRowView)
                    HStack(spacing: 4) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Spacer for alignment
                        Spacer()
                            .frame(width: 0)
                    }
                }
            }
            .padding(.leading, 48)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

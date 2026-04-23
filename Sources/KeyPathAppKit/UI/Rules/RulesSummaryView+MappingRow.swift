import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Mapping Row View

struct MappingRowView: View {
    let mapping: (input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)
    let layerActivator: MomentaryActivator?
    var leaderKeyDisplay: String = "␣ Space"
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    /// Extract app identifier from push-msg launch output
    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: mapping.output)
    }

    /// Extract system action identifier from push-msg output or direct output labels.
    private var systemActionIdentifier: String? {
        if let extracted = KeyboardVisualizationViewModel.extractSystemActionIdentifier(from: mapping.output) {
            return extracted
        }
        return SystemActionInfo.find(byOutput: mapping.output)?.id
    }

    /// Extract URL from push-msg open output.
    private var urlIdentifier: String? {
        KeyboardVisualizationViewModel.extractUrlIdentifier(from: mapping.output)
    }

    /// Extract target layer from layer-switch output.
    private var layerSwitchIdentifier: String? {
        LayerInfo.extractLayerName(from: mapping.output)
    }

    private var isEditable: Bool {
        onEditMapping != nil
    }

    var body: some View {
        Button(action: {
            if let onEdit = onEditMapping {
                onEdit(mapping.id)
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Show layer activator if present
                    if layerActivator != nil {
                        HStack(spacing: 4) {
                            Text("Hold")
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(.accentColor)
                            Text(leaderKeyDisplay)
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(KeycapStyle.textColor)
                        }
                        .modifier(KeycapStyle())

                        Text("+")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Text(prettyKeyName(mapping.input))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())
                        .accessibilityIdentifier("rules-summary-mapping-row-input-\(mapping.id)")

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)

                    // Show rich chips for app/system/url/layer actions, otherwise show key chip
                    if let appId = appLaunchIdentifier {
                        RulesSummaryAppLaunchChip(appIdentifier: appId)
                    } else if let actionId = systemActionIdentifier {
                        RulesSummarySystemActionChip(actionIdentifier: actionId)
                    } else if let urlId = urlIdentifier {
                        RulesSummaryURLChip(urlString: urlId)
                    } else if let layerName = layerSwitchIdentifier {
                        RulesSummaryLayerSwitchChip(layerName: layerName)
                    } else {
                        Text(prettyKeyName(mapping.output))
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(KeycapStyle.textColor)
                            .modifier(KeycapStyle())
                    }

                    // Show rule name/title if provided
                    if let title = mapping.description, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Behavior summary for custom rules on same line
                    if let behavior = mapping.behavior {
                        RuleBehaviorSummaryView(behavior: behavior)
                    }

                    Spacer(minLength: 0)

                    // Action buttons - subtle icons that appear on hover
                    if onEditMapping != nil || onDeleteMapping != nil {
                        HStack(spacing: 4) {
                            if let onEdit = onEditMapping {
                                Button {
                                    onEdit(mapping.id)
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.footnote.weight(.medium))
                                        .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            if let onDelete = onDeleteMapping {
                                Button {
                                    onDelete(mapping.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.footnote.weight(.medium))
                                        .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            // Spacer for alignment
                            Spacer()
                                .frame(width: 0)
                        }
                    }
                }

                if let shiftedOutput = mapping.shiftedOutput {
                    RuleModifierVariantView(label: "⇧ Shift", output: shiftedOutput)
                }
            }
            .padding(.leading, 48)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && isEditable ? Color.primary.opacity(0.03) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-mapping-row-button-\(mapping.id)")
        .accessibilityLabel("Edit mapping for \(prettyKeyName(mapping.input))")
        .onHover { hovering in
            isHovered = hovering
            if isEditable {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

}

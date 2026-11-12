import KeyPathCore
import KeyPathRulesCore
import SwiftUI

/// A readable shortcut reference. Preview interactions never move real windows.
struct WindowSnappingView: View {
    let mappings: [KeyMapping]
    let convention: WindowKeyConvention
    let activationMode: WindowSnappingActivationMode
    let onConventionChange: (WindowKeyConvention) -> Void
    var onActivationModeChange: ((WindowSnappingActivationMode) -> Void)?
    @State private var changingActivation = false
    @State private var preview: SnapZone = .left
    @FocusState private var focusedZone: SnapZone?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let zones: [SnapZone] = [.left, .right, .maximize, .center, .topLeft, .topRight, .bottomLeft, .bottomRight]

    private var activationDescription: String {
        activationDescription(action: String(localized: "action", comment: "Window snapping: placeholder for the zone key, as in 'Hold Space → W → action'"))
    }

    private func activationDescription(action: String) -> String {
        if activationMode == .quickLauncher { return String(localized: "Hold Hyper → W → \(action)") }
        let preference = PreferencesService.shared.leaderKeyPreference
        let key = ["space", "spc"].contains(preference.key) ? String(localized: "Space", comment: "Key name: the space bar") : preference.key.uppercased()
        return PreferencesService.shared.contextHUDTriggerMode == .holdToShow
            ? String(localized: "Hold \(key) → W → \(action)")
            : String(localized: "Tap \(key) → W → \(action)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionContentGap) {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activation").font(.body.weight(.medium))
                        Text(activationDescription).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…") { changingActivation = true }
                        .settingsAction()
                        .accessibilityIdentifier("window-snapping-change-activation")
                        .popover(isPresented: $changingActivation) {
                            VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                                Text("Activation method").font(.headline)
                                Picker("Activation method", selection: Binding(
                                    get: { activationMode },
                                    set: { onActivationModeChange?($0); changingActivation = false }
                                )) {
                                    Text("Leader Key").tag(WindowSnappingActivationMode.leader)
                                    Text("Quick Launcher").tag(WindowSnappingActivationMode.quickLauncher)
                                }
                                .pickerStyle(.radioGroup)
                                .accessibilityIdentifier("window-snapping-activation-mode-picker")
                                Text("Any required setup is checked when you enable Window Snapping.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.padding(SettingsDesign.cardInset).frame(width: 280)
                        }
                }
            }
            PermissionStatusBanner()
            SettingsCard {
                VStack(spacing: SettingsDesign.rowGap) {
                    SettingsControlRow(title: String(localized: "Key layout"), icon: "keyboard") {
                        Picker("Key layout", selection: Binding(get: { convention }, set: { onConventionChange($0) })) {
                            Text("Standard").tag(WindowKeyConvention.standard)
                            Text("Vim").tag(WindowKeyConvention.vim)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
                        .accessibilityIdentifier("window-snapping-convention-picker")
                    }
                    Divider()
                    HStack(spacing: 16) {
                        desktopPreview(preview).frame(width: 140, height: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(preview)).font(.headline)
                            Text(activationDescription(action: preview.key(for: convention)))
                                .font(.callout).foregroundStyle(.secondary)
                            Text("Preview only — your windows stay in place.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(zones, id: \.rawValue) { zone in
                            Button { preview = zone } label: {
                                VStack(spacing: 6) {
                                    desktopPreview(zone).frame(width: 62, height: 38)
                                    Text(title(zone)).font(.caption).foregroundStyle(.primary)
                                    Text(zone.key(for: convention)).font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(preview == zone ? Color.accentColor.opacity(0.1) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: SettingsDesign.optionRadius))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focused($focusedZone, equals: zone)
                            .onHover { if $0 { preview = zone } }
                            .accessibilityLabel("Preview \(title(zone)), shortcut \(zone.key(for: convention))")
                            .accessibilityIdentifier("window-snapping-preview-\(zone.rawValue)")
                        }
                    }
                }
            }
            SettingsCard {
                DisclosureGroup {
                    VStack(spacing: 12) {
                        shortcutRow(String(localized: "Previous / next display"), keys: "[  /  ]", icon: "display.2")
                        Divider()
                        shortcutRow(String(localized: "Previous / next Space"), keys: convention == .standard ? ",  /  ." : "A  /  S", icon: "square.stack.3d.up")
                        Divider()
                        shortcutRow(String(localized: "Undo last move"), keys: "Z", icon: "arrow.uturn.backward")
                    }.padding(.top, 12)
                } label: {
                    Text("More shortcuts").accessibilityIdentifier("window-snapping-more-shortcuts")
                }
            }
        }
        .onChange(of: focusedZone) { _, zone in if let zone { preview = zone } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: preview)
    }

    private func shortcutRow(_ label: String, keys: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(keys).font(.body.monospaced())
        }.font(.callout)
    }

    private func title(_ zone: SnapZone) -> String {
        switch zone {
        case .left: String(localized: "Left Half")
        case .right: String(localized: "Right Half")
        case .topLeft: String(localized: "Top Left", comment: "Window snapping zone title")
        case .topRight: String(localized: "Top Right", comment: "Window snapping zone title")
        case .bottomLeft: String(localized: "Bottom Left", comment: "Window snapping zone title")
        case .bottomRight: String(localized: "Bottom Right", comment: "Window snapping zone title")
        case .maximize: String(localized: "Maximize", comment: "Window snapping zone title")
        case .center: String(localized: "Center", comment: "Window snapping zone title")
        }
    }

    /// Normalized window geometry reflects each action, independent of the display size.
    private func desktopPreview(_ zone: SnapZone) -> some View {
        GeometryReader { geometry in
            let rect = zone.previewRect
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.35)))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: (geometry.size.width - 8) * rect.width, height: (geometry.size.height - 8) * rect.height)
                        .offset(x: 4 + (geometry.size.width - 8) * rect.minX, y: 4 + (geometry.size.height - 8) * rect.minY)
                }
        }.accessibilityHidden(true)
    }
}

extension SnapZone {
    var previewRect: CGRect {
        switch self {
        case .left: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        }
    }
}

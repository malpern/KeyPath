import AppKit
import KeyPathCore
import KeyPathPermissions
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case status
    case rules
    case simulator
    case general
    case advanced

    var title: String {
        switch self {
        case .general: "General"
        case .status: "Status"
        case .rules: "Rules"
        case .simulator: "Simulator"
        case .advanced: "Repair/Remove"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .status: "gauge.with.dots.needle.bottom.50percent"
        case .rules: "list.bullet"
        case .simulator: "keyboard"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    static var visibleTabs: [SettingsTab] {
        if FeatureFlags.simulatorAndVirtualKeysEnabled {
            return allCases
        }
        return allCases.filter { $0 != .simulator }
    }
}

struct SettingsContainerView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var selection: SettingsTab = .status
    @State private var canManageRules: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabPicker(selection: $selection, rulesEnabled: canManageRules)
                .padding(.bottom, 12)

            Group {
                switch selection {
                case .general:
                    GeneralSettingsTabView()
                case .status:
                    StatusSettingsTabView()
                case .rules:
                    if canManageRules {
                        RulesTabView()
                    } else {
                        RulesDisabledView(onOpenStatus: { selection = .status })
                    }
                case .simulator:
                    SimulatorView()
                case .advanced:
                    AdvancedSettingsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, maxWidth: 680, minHeight: 550, idealHeight: 700)
        .task { await refreshCanManageRules() }
        .onAppear {
            if !FeatureFlags.simulatorAndVirtualKeysEnabled, selection == .simulator {
                selection = .advanced
            }
            LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
        }
        .onDisappear {
            LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsGeneral)) { _ in
            selection = .general
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsStatus)) { _ in
            selection = .status
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDiagnostics)) { _ in
            selection = .advanced
            // Post another notification to switch to errors tab within advanced settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .showErrorsTab, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRules)) { _ in
            selection = canManageRules ? .rules : .status
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSimulator)) { _ in
            guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
                selection = .status
                return
            }
            selection = .simulator
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task { await refreshCanManageRules() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAdvanced)) { _ in
            selection = .advanced
        }
    }

    private func refreshCanManageRules() async {
        let context = await kanataManager.inspectSystemContext()
        await MainActor.run {
            canManageRules = context.services.isHealthy && context.services.kanataRunning
            if !canManageRules, selection == .rules {
                selection = .status
            }
        }
    }
}

// MARK: - Settings Tab Picker

private struct SettingsTabPicker: View {
    @Binding var selection: SettingsTab
    let rulesEnabled: Bool

    var body: some View {
        HStack(spacing: 24) {
            ForEach(SettingsTab.visibleTabs, id: \.self) { tab in
                let disabled = (tab == .rules && !rulesEnabled)
                SettingsTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    disabled: disabled,
                    action: {
                        guard !disabled else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selection = .status
                            }
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(disabled ? Color.secondary.opacity(0.35)
                        : (isSelected ? Color.accentColor : Color.secondary))
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                disabled ? Color(NSColor.separatorColor)
                                    : (isSelected ? Color.accentColor : Color(NSColor.separatorColor)),
                                lineWidth: isSelected && !disabled ? 2 : 1
                            )
                    )

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(disabled ? .secondary.opacity(0.6)
                        : (isSelected ? .primary : .secondary))
            }
            .frame(width: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(disabled)
        .accessibilityIdentifier("settings-tab-\(tab.accessibilityId)")
        .accessibilityLabel(tab.title)
    }
}

extension SettingsTab {
    var accessibilityId: String {
        switch self {
        case .status: "status"
        case .rules: "rules"
        case .simulator: "simulator"
        case .general: "general"
        case .advanced: "repair"
        }
    }
}

private struct RulesDisabledView: View {
    let onOpenStatus: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "power")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Turn on Kanata to manage rules.")
                .font(.title3.weight(.semibold))
            Text("Start the service on the Status tab, then return to manage rules.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button(action: onOpenStatus) {
                Label("Go to Status", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("settings-go-to-status-button")
            .accessibilityLabel("Go to Status")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import AppKit
import KeyPathCore
import KeyPathPermissions
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case status
    case rules
    case general
    case advanced

    var title: String {
        switch self {
        case .general: "General"
        case .status: "Status"
        case .rules: "Rules"
        case .advanced: "Repair/Remove"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .status: "gauge.with.dots.needle.bottom.50percent"
        case .rules: "list.bullet"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    static var visibleTabs: [SettingsTab] {
        allCases
    }
}

struct SettingsContainerView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @State private var selection: SettingsTab = .status
    @State private var canManageRules: Bool = true
    private var requiredSettingsWidth: CGFloat {
        SettingsTabLayout.requiredWidth(forTabCount: SettingsTab.visibleTabs.count)
    }

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
                case .advanced:
                    AdvancedSettingsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: requiredSettingsWidth,
            idealWidth: requiredSettingsWidth,
            maxWidth: requiredSettingsWidth,
            minHeight: 550,
            idealHeight: 700
        )
        .task { await refreshCanManageRules() }
        .onAppear {
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
            selection = .advanced
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
        HStack(spacing: SettingsTabLayout.spacing) {
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
        .padding(.horizontal, SettingsTabLayout.horizontalPadding)
        .padding(.top, SettingsTabLayout.topPadding)
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
                    .font(.title)
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
            .frame(width: SettingsTabLayout.buttonWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(disabled)
        .accessibilityIdentifier("settings-tab-\(tab.accessibilityId)")
        .accessibilityLabel(tab.title)
    }
}

private enum SettingsTabLayout {
    static let buttonWidth: CGFloat = 120
    static let spacing: CGFloat = 24
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 28
    static let minimumWindowWidth: CGFloat = 680

    static func requiredWidth(forTabCount tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return minimumWindowWidth }
        let totalButtonWidth = CGFloat(tabCount) * buttonWidth
        let totalSpacing = CGFloat(max(0, tabCount - 1)) * spacing
        let totalPadding = horizontalPadding * 2
        return max(minimumWindowWidth, totalButtonWidth + totalSpacing + totalPadding)
    }
}

extension SettingsTab {
    var accessibilityId: String {
        switch self {
        case .status: "status"
        case .rules: "rules"
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
                .font(.largeTitle.weight(.semibold))
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

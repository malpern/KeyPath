import AppKit
import KeyPathCore
import KeyPathInstallationWizard
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

    var body: some View {
        TabView(selection: $selection) {
            StatusSettingsTabView()
                .tabItem {
                    Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .accessibilityIdentifier("settings-tab-status")
                }
                .tag(SettingsTab.status)

            Group {
                if canManageRules {
                    RulesTabView()
                } else {
                    RulesDisabledView(onOpenStatus: { selection = .status })
                }
            }
            .tabItem {
                Label("Rules", systemImage: "list.bullet")
                    .accessibilityIdentifier("settings-tab-rules")
            }
            .tag(SettingsTab.rules)

            GeneralSettingsTabView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                        .accessibilityIdentifier("settings-tab-general")
                }
                .tag(SettingsTab.general)

            AdvancedSettingsTabView()
                .tabItem {
                    Label("Repair/Remove", systemImage: "wrench.and.screwdriver")
                        .accessibilityIdentifier("settings-tab-repair")
                }
                .tag(SettingsTab.advanced)
        }
        .accessibilityIdentifier("settings-window")
        .background(tabShortcutHandlers)
        .frame(
            minWidth: 680,
            idealWidth: 680,
            maxWidth: 680,
            minHeight: 550,
            idealHeight: 700
        )
        .task { await refreshCanManageRules() }
        .onAppear {
            LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
            applyPendingSettingsNavigationIfNeeded()
        }
        .onDisappear {
            LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsGeneral)) { _ in
            selection = .general
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsGeneral)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsStatus)) { _ in
            selection = .status
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsStatus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSystemStatus)) { _ in
            selection = .status
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsSystemStatus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsLogs)) { _ in
            selection = .general
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsLogs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDiagnostics)) { _ in
            selection = .advanced
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .showErrorsTab, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRules)) { notification in
            selection = canManageRules ? .rules : .status
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsRules)
            AppLogger.shared.log("🎯 [Settings] Selected Rules tab target=\(notification.userInfo?[SettingsNavigationUserInfo.ruleCollectionTarget] as? String ?? "none")")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSimulator)) { _ in
            selection = .advanced
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsSimulator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task { await refreshCanManageRules() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAdvanced)) { _ in
            selection = .advanced
            SettingsNavigationCoordinator.shared.clearIfMatches(.openSettingsAdvanced)
        }
    }

    private var tabShortcutHandlers: some View {
        VStack {
            Button("") { selection = .status }
                .keyboardShortcut("1", modifiers: .command)
                .accessibilityIdentifier("settings-shortcut-status-button")
            Button("") { selection = canManageRules ? .rules : selection }
                .keyboardShortcut("2", modifiers: .command)
                .accessibilityIdentifier("settings-shortcut-rules-button")
            Button("") { selection = .general }
                .keyboardShortcut("3", modifiers: .command)
                .accessibilityIdentifier("settings-shortcut-general-button")
            Button("") { selection = .advanced }
                .keyboardShortcut("4", modifiers: .command)
                .accessibilityIdentifier("settings-shortcut-repair-button")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    private func applyPendingSettingsNavigationIfNeeded() {
        guard let request = SettingsNavigationCoordinator.shared.consumePendingRequest() else { return }
        switch request.notification {
        case .openSettingsGeneral, .openSettingsLogs:
            selection = .general
        case .openSettingsRules:
            selection = canManageRules ? .rules : .status
            AppLogger.shared.log("🎯 [Settings] Applied pending Rules navigation target=\(request.userInfo?[SettingsNavigationUserInfo.ruleCollectionTarget] as? String ?? "none")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .openSettingsRules, object: nil, userInfo: request.userInfo)
            }
        case .openSettingsAdvanced, .openSettingsSimulator:
            selection = .advanced
        default:
            selection = .status
        }
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

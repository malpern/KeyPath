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
                .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(SettingsTab.status)

            Group {
                if canManageRules {
                    RulesTabView()
                } else {
                    RulesDisabledView(onOpenStatus: { selection = .status })
                }
            }
            .tabItem { Label("Rules", systemImage: "list.bullet") }
            .tag(SettingsTab.rules)

            GeneralSettingsTabView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AdvancedSettingsTabView()
                .tabItem { Label("Repair/Remove", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
        }
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

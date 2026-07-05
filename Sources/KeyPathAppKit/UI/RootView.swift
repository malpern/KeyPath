import SwiftUI

struct RootView: View {
    @State private var showingWhatsNew = false
    // Keep lightweight “modal” affordances for menu actions even though the main window is now a splash.
    @State private var showingEmergencyStopDialog = false
    @State private var showingUninstallDialog = false
    @State private var showingSimpleModsDialog = false

    @Environment(KanataViewModel.self) private var kanataVM

    var body: some View {
        @Bindable var kanataVM = kanataVM

        SplashView()
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView()
                    .onDisappear {
                        WhatsNewTracker.markAsSeen()
                    }
            }
            .sheet(isPresented: $showingEmergencyStopDialog) {
                EmergencyStopDialog(isActivated: kanataVM.emergencyStopActivated)
            }
            .sheet(isPresented: $showingUninstallDialog) {
                UninstallKeyPathDialog()
                    .environment(kanataVM)
            }
            .sheet(isPresented: $showingSimpleModsDialog) {
                SimpleModsView(configPath: kanataVM.configPath)
                    .environment(kanataVM)
            }
            .sheet(isPresented: $kanataVM.showRuleConflictDialog) {
                if let context = kanataVM.pendingRuleConflict {
                    RuleConflictResolutionDialog(
                        context: context,
                        onChoice: { choice in
                            kanataVM.resolveRuleConflict(with: choice)
                        },
                        onCancel: {
                            kanataVM.resolveRuleConflict(with: nil)
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $kanataVM.showMappingConflictDialog) {
                if let context = kanataVM.pendingMappingConflict {
                    MappingConflictResolutionDialog(
                        context: context,
                        onChoice: { collectionID in
                            kanataVM.resolveMappingConflict(disabling: collectionID)
                        },
                        onCancel: {
                            kanataVM.resolveMappingConflict(disabling: nil)
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showEmergencyStop)) { _ in
                showingEmergencyStopDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showUninstall)) { _ in
                showingUninstallDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSimpleMods)) { _ in
                showingSimpleModsDialog = true
            }
            .task {
                if WhatsNewTracker.shouldShowWhatsNew() {
                    showingWhatsNew = true
                }
            }
    }
}

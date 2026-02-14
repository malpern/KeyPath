import SwiftUI

struct RootView: View {
    @State private var showingWhatsNew = false
    // Keep lightweight “modal” affordances for menu actions even though the main window is now a splash.
    @State private var showingEmergencyStopDialog = false
    @State private var showingUninstallDialog = false
    @State private var showingSimpleModsDialog = false

    @Environment(KanataViewModel.self) private var kanataVM

    var body: some View {
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEmergencyStop"))) { _ in
                showingEmergencyStopDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUninstall"))) { _ in
                showingUninstallDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSimpleMods"))) { _ in
                showingSimpleModsDialog = true
            }
            .task {
                if WhatsNewTracker.shouldShowWhatsNew() {
                    showingWhatsNew = true
                }
            }
    }
}

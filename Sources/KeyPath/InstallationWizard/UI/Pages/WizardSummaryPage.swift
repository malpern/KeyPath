import SwiftUI

/// Simplified summary page using extracted components
struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let isInitializing: Bool

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
        kanataViewModel.underlyingManager
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header - changes when everything is complete
                Group {
                    if isEverythingComplete {
                        WizardPageHeader(
                            icon: "keyboard.badge.checkmark",
                            title: "KeyPath Ready",
                            subtitle: "Your keyboard customization tool is fully configured",
                            status: .success
                        )
                    } else {
                        WizardPageHeader(
                            icon: "keyboard.fill",
                            title: "Welcome to KeyPath",
                            subtitle: "Set up your keyboard customization tool",
                            status: .info
                        )
                    }
                }
                .padding(.bottom, WizardDesign.Spacing.sectionGap)

                // System Status Overview
                ScrollView {
                    WizardSystemStatusOverview(
                        systemState: systemState,
                        issues: issues,
                        stateInterpreter: stateInterpreter,
                        onNavigateToPage: onNavigateToPage,
                        kanataIsRunning: kanataManager.isRunning
                    )
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }
                .frame(maxHeight: geometry.size.height * 0.5) // Limit scroll area

                Spacer(minLength: WizardDesign.Spacing.itemGap)

                // Action Section
                WizardActionSection(
                    systemState: systemState,
                    isFullyConfigured: isEverythingComplete,
                    onStartService: onStartService,
                    onDismiss: onDismiss
                )
                .padding(.bottom, WizardDesign.Spacing.pageVertical)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Properties

    private var isEverythingComplete: Bool {
        // Check if system is active and running
        guard systemState == .active && kanataManager.isRunning else {
            return false
        }

        // Check that there are no issues
        guard issues.isEmpty else {
            return false
        }

        // Additional check: Verify TCP communication is properly configured
        // NOTE: Kanata v1.9.0 TCP does NOT require authentication
        // No token check needed - just verify service has TCP configuration

        // Check if the LaunchDaemon plist exists and has TCP configuration
        let plistPath = "/Library/LaunchDaemons/com.keypath.kanata.plist"
        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        guard plistExists else {
            return false // Service plist doesn't exist
        }

        // Verify plist has TCP port argument
        if let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let args = plist["ProgramArguments"] as? [String]
        {
            let hasTCPPort = args.contains("--port")
            guard hasTCPPort else {
                return false // Service uses old TCP configuration
            }
        } else {
            return false // Can't read plist or parse arguments
        }

        // Everything is properly configured
        return true
    }
}

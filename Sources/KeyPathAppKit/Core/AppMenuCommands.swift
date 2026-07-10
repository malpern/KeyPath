import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import Sparkle
import SwiftUI

/// Encapsulates all menu bar command definitions for the KeyPath app.
///
/// Extracted from `KeyPathApp.body` to keep the App struct a thin routing layer.
struct AppMenuCommands: Commands {
    let viewModel: KanataViewModel
    let appDelegate: AppDelegate

    var body: some Commands {
        // Replace default "AppName" menu with "KeyPath" menu
        CommandGroup(replacing: .appInfo) {
            Button("About KeyPath") {
                showAboutPanel()
            }

            Divider()

            CheckForUpdatesView(updater: UpdateService.shared.updater)
        }

        // Add File menu with Settings tabs shortcuts
        CommandGroup(replacing: .newItem) {
            Button(
                action: {
                    openPreferencesTab(.openSettingsAdvanced)
                },
                label: {
                    Label("Repair/Remove\u{2026}", systemImage: "wrench.and.screwdriver")
                }
            )
            .keyboardShortcut(",", modifiers: .command)

            Button(
                action: {
                    openPreferencesTab(.openSettingsRules)
                },
                label: {
                    Label("Rules\u{2026}", systemImage: "list.bullet")
                }
            )
            .keyboardShortcut("r", modifiers: .command)

            Button(
                action: {
                    openPreferencesTab(.openSettingsAdvanced)
                },
                label: {
                    Label("Simulator (Repair/Remove)\u{2026}", systemImage: "keyboard")
                }
            )

            Button(
                action: {
                    openPreferencesTab(.openSettingsSystemStatus)
                },
                label: {
                    Label("System Status\u{2026}", systemImage: "gauge.with.dots.needle.67percent")
                }
            )
            .keyboardShortcut("s", modifiers: .command)

            Button(
                action: {
                    openPreferencesTab(.openSettingsLogs)
                },
                label: {
                    Label("Logs\u{2026}", systemImage: "doc.text.magnifyingglass")
                }
            )
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Install wizard...") {
                NotificationCenter.default.post(name: .showWizard, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Install Command Line Tool...") {
                installCommandLineTool()
            }

            Divider()

            Button(
                action: {
                    openConfigInEditor(viewModel: viewModel)
                },
                label: {
                    Label("Edit Config", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            )
            .keyboardShortcut("o", modifiers: .command)

            Button("Simple Key Mappings\u{2026}") {
                appDelegate.showMainWindow()
                NotificationCenter.default.post(name: .showSimpleMods, object: nil)
            }

            Divider()

            Button(
                action: {
                    CommandPaletteWindowController.shared.toggle()
                },
                label: {
                    Label("Command Palette", systemImage: "command")
                }
            )
            .keyboardShortcut("k", modifiers: .command)

            Button(
                action: {
                    RecentKeypressesWindowController.shared.toggle()
                },
                label: {
                    Label("Recent Keypresses", systemImage: "list.bullet.rectangle")
                }
            )
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Input Capture Experiment") {
                InputCaptureExperimentWindowController.shared.showWindow()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Mapper") {
                NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("Stop KeyPath Runtime...") {
                let alert = NSAlert()
                alert.messageText = "Stop KeyPath Runtime?"
                alert.informativeText = "This will stop keyboard remapping. You can restart it from the overlay or by relaunching KeyPath."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Stop")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    Task { @MainActor in
                        let stopped = await appDelegate.viewModel?.stopKanata(reason: "Menu stop") ?? false
                        if stopped {
                            AppLogger.shared.log("🛑 [Menu] Runtime stopped by user")
                        } else {
                            AppLogger.shared.warn("⚠️ [Menu] Stop requested but nothing to stop")
                        }
                    }
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button(
                role: .destructive,
                action: {
                    appDelegate.showMainWindow()
                    NotificationCenter.default.post(name: .showUninstall, object: nil)
                },
                label: {
                    Label("Uninstall KeyPath\u{2026}", systemImage: "trash")
                }
            )

            // Hidden instant uninstall (no confirmation, just admin prompt)
            Button(
                role: .destructive,
                action: {
                    Task { @MainActor in
                        AppLogger.shared.log("🗑️ [InstantUninstall] \u{2325}\u{2318}U triggered - performing immediate uninstall")
                        let report = await InstallerEngine().uninstall(
                            deleteConfig: false,
                            using: PrivilegeBroker()
                        )
                        if report.success {
                            AppLogger.shared.log("✅ [InstantUninstall] Uninstall completed successfully")
                            NSApplication.shared.terminate(nil)
                        } else {
                            AppLogger.shared.log("❌ [InstantUninstall] Uninstall failed")
                            let alert = NSAlert()
                            alert.messageText = "Uninstall Failed"
                            alert.informativeText = report.failureReason ?? "An unknown error occurred during uninstall"
                            alert.alertStyle = .critical
                            alert.runModal()
                        }
                    }
                },
                label: {
                    Text("") // Hidden menu item
                }
            )
            .keyboardShortcut("u", modifiers: [.control, .option, .command])
            .hidden() // Hide from menu but keep keyboard shortcut active
        }

        // View menu — exposes global hotkeys for discoverability
        CommandMenu("View") {
            Button("Toggle Overlay") {
                LiveKeyboardOverlayController.shared.toggle()
            }
            .keyboardShortcut("k", modifiers: [.option, .command])

            Button("Center Overlay") {
                NotificationCenter.default.post(name: NSNotification.Name("ResetOverlayPosition"), object: nil)
            }
            .keyboardShortcut("l", modifiers: [.option, .command])

            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: NSNotification.Name("ToggleInspectorDrawer"), object: nil)
            }
            .keyboardShortcut("d", modifiers: [.option, .command])
        }

        // Help menu -- single entry opens navigable help browser
        CommandGroup(replacing: .help) {
            Button("KeyPath Help") {
                HelpWindowController.shared.showBrowser()
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    // MARK: - Private Helpers

    private func showAboutPanel() {
        let info = BuildInfo.current()
        var detailLines = ["Keys that do more.", "", "Build \(info.build) \u{2022} \(info.git) \u{2022} \(info.date)"]
        if let kanataVersion = info.kanataVersion {
            detailLines.append("Kanata \(kanataVersion)")
        }
        let details = detailLines.joined(separator: "\n")
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                    string: details,
                    attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                ),
                NSApplication.AboutPanelOptionKey.applicationName: "KeyPath",
                NSApplication.AboutPanelOptionKey.applicationVersion: info.version,
                NSApplication.AboutPanelOptionKey.version: "Build \(info.build)"
            ]
        )
    }

    private func installCommandLineTool() {
        if !CommandLineToolInstaller.canReplaceExistingDestination() {
            let alert = NSAlert()
            alert.messageText = "Command Line Tool Already Exists"
            alert.informativeText = """
            \(CommandLineToolInstaller.linkPath) already exists and is not a KeyPath command-line tool link.

            Remove or rename the existing file before installing KeyPath's command-line tool.
            """
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Install Command Line Tool?"
        alert.informativeText = """
        This installs a terminal command at:
        \(CommandLineToolInstaller.linkPath)

        The command points to the signed CLI inside KeyPath.app. Opening KeyPath.app remains the primary way to launch KeyPath.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await CommandLineToolInstaller.install()
                let success = NSAlert()
                success.messageText = "Command Line Tool Installed"
                success.informativeText = """
                You can now run:
                keypath-cli system inspect

                The command points to the CLI inside KeyPath.app.
                """
                success.alertStyle = .informational
                success.runModal()
            } catch {
                let failure = NSAlert()
                failure.messageText = "Command Line Tool Install Failed"
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .critical
                failure.runModal()
            }
        }
    }
}

/// SwiftUI wrapper for Sparkle's "Check for Updates" menu item
struct CheckForUpdatesView: View {
    private var updateService = UpdateService.shared

    /// The updater parameter is kept for API compatibility but we use the shared service
    init(updater _: SPUUpdater?) {}

    var body: some View {
        Button("Check for Updates\u{2026}") {
            updateService.checkForUpdates()
        }
        .disabled(!updateService.canCheckForUpdates)
    }
}

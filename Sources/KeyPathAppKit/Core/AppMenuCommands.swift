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

            Button("Set Up KeyPath…") {
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

            #if DEBUG
            Button("Input Capture Experiment") {
                InputCaptureExperimentWindowController.shared.showWindow()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            #endif

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

        }

        // Extend the standard View menu with the overlay controls.
        CommandGroup(after: .toolbar) {
            Button("Toggle Overlay") {
                LiveKeyboardOverlayController.shared.toggle()
            }
            .keyboardShortcut("k", modifiers: [.option, .command])

            Button("Center Overlay") {
                LiveKeyboardOverlayController.shared.showResetCentered()
            }
            .keyboardShortcut("l", modifiers: [.option, .command])

            Button("Toggle Inspector") {
                let overlay = LiveKeyboardOverlayController.shared
                if !overlay.isVisible {
                    overlay.isVisible = true
                }
                overlay.bringToFront()
                overlay.toggleDrawerWithHighlight()
            }
            .keyboardShortcut("d", modifiers: [.option, .command])
        }

        // Help menu -- single entry opens navigable help browser
        CommandGroup(replacing: .help) {
            Button("KeyPath Help") {
                HelpWindowController.shared.showBrowser()
            }
            .keyboardShortcut("?", modifiers: .command)

            if FirstSuccessOnboardingGate.supportsTour() {
                Divider()

                Button(
                    action: {
                        replayFirstSuccessTour()
                    },
                    label: {
                        Text(
                            "Replay KeyPath Tour…",
                            bundle: KeyPathAppKitResources.bundle,
                            comment: "Help menu command that reopens KeyPath's optional keyboard onboarding tour."
                        )
                    }
                )
                .accessibilityIdentifier("menu-replay-keypath-tour")
            }
        }
    }

    // MARK: - Private Helpers

    private func showAboutPanel() {
        let info = BuildInfo.current()
        var detailLines = ["Keys that do more.", "", "Build \(info.build) \u{2022} \(info.git) \u{2022} \(info.date)"]
        if let kanataVersion = info.kanataVersion {
            detailLines.append("Kanata \(kanataVersion)")
        }
        if UpdateService.shared.usesManualDownloads {
            detailLines.append("\nDownload updates from the KeyPath menu. Quit KeyPath before replacing the app.")
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

    @MainActor
    private func replayFirstSuccessTour() {
        AppLogger.shared.log("🎓 [Menu] Replaying first-success tour")
        FirstSuccessOnboardingWindowController.show(
            kanataViewModel: viewModel,
            source: .replay
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
        Button(updateService.usesManualDownloads ? "Download Update…" : "Check for Updates…") {
            updateService.checkForUpdates()
        }
        .disabled(!updateService.canCheckForUpdates)
    }
}

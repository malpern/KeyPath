import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathRulesCore
import SwiftUI

/// Presents the first-success learning path after a healthy first setup.
@MainActor
final class FirstSuccessOnboardingWindowController: NSWindowController {
    private static var currentController: FirstSuccessOnboardingWindowController?
    private let actionCoordinator: FirstSuccessOnboardingActionCoordinator

    static func show(kanataViewModel: KanataViewModel?) {
        if let currentController {
            currentController.showWindow(nil)
            currentController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = FirstSuccessOnboardingWindowController(kanataViewModel: kanataViewModel)
        currentController = controller
        LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
        controller.showWindow(nil)
        FirstSuccessOnboardingGate.markPresented()
    }

    private init(kanataViewModel: KanataViewModel?) {
        let actionCoordinator = FirstSuccessOnboardingActionCoordinator()
        let existingLauncher = kanataViewModel?.underlyingManager.rulesManager
            .ruleCollections.first(where: {
                $0.id == RuleCollectionIdentifier.launcher
            })
        let catalogLauncherConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
            .configuration
        let launcherChoice = FirstSuccessLauncherChoiceModel(
            occupiedCanonicalKeys: Self.occupiedLauncherKeys(
                existing: existingLauncher,
                catalogConfiguration: catalogLauncherConfiguration
            )
        )
        let dialog = FirstSuccessOnboardingDialog(
            actionCoordinator: actionCoordinator,
            makeCapsLockEscape: {
                if Self.usesNonMutatingVisualPreviewActions() {
                    return await Self.previewActionResult()
                }
                guard let kanataViewModel else { return .failed }
                return await Self.installCapsLockEscape(using: kanataViewModel)
            },
            addHyperHold: {
                if Self.usesNonMutatingVisualPreviewActions() {
                    return await Self.previewActionResult()
                }
                guard let kanataViewModel else { return .failed }
                return await Self.installQuickLauncher(using: kanataViewModel)
            },
            saveLauncherShortcut: { mapping in
                if Self.usesNonMutatingVisualPreviewActions() {
                    return await Self.previewActionResult()
                }
                guard let kanataViewModel else { return .failed }
                return await Self.saveLauncherShortcut(
                    mapping,
                    using: kanataViewModel
                )
            },
            finishInRules: {
                FirstSuccessOnboardingWindowController.dismiss()
                openPreferencesTab(
                    .openSettingsRules,
                    userInfo: [
                        SettingsNavigationUserInfo.ruleCollectionTarget:
                            RuleCollectionIdentifier.launcher.uuidString,
                    ]
                )
            },
            dismiss: {
                FirstSuccessOnboardingWindowController.dismiss()
            },
            launcherChoice: launcherChoice
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyPath"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = FirstSuccessOnboardingStyle.initialBackgroundNSColor
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 960, height: 650)
        window.center()

        self.actionCoordinator = actionCoordinator
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: dialog)
        window.delegate = self
        actionCoordinator.actionStateDidChange = { [weak window] isActionInFlight in
            window?.standardWindowButton(.closeButton)?.isEnabled = !isActionInFlight
        }
    }

    /// Debug-only seam for reviewing every visual state without replacing a
    /// developer's live keyboard configuration. Production builds always use
    /// the canonical PackInstaller actions above.
    static func usesNonMutatingVisualPreviewActions(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
            environment["KEYPATH_FIRST_SUCCESS_PREVIEW_ACTIONS"] == "1"
        #else
            false
        #endif
    }

    /// Hold the applying scene long enough for installed-app visual QA to
    /// inspect the causal Metal transition. This path exists only in DEBUG and
    /// never writes keyboard state; production actions use their real save and
    /// reload duration.
    private static func previewActionResult() async -> FirstSuccessOnboardingSession.ActionResult {
        try? await Task<Never, Never>.sleep(for: .seconds(8))
        return .applied
    }

    static func dismiss() {
        guard let controller = currentController else { return }
        guard controller.actionCoordinator.canDismiss else {
            NSSound.beep()
            return
        }
        controller.close()
        Self.currentController = nil
    }

    private static func installCapsLockEscape(
        using viewModel: KanataViewModel
    ) async -> FirstSuccessOnboardingSession.ActionResult {
        let manager = viewModel.underlyingManager.rulesManager

        guard let catalogConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })?
            .configuration
        else {
            AppLogger.shared.error("❌ [FirstSuccessOnboarding] Caps Lock catalog collection is unavailable")
            return .failed
        }

        guard let configuration = escapeOnlyCapsLockConfiguration(from: catalogConfiguration) else {
            AppLogger.shared.error("❌ [FirstSuccessOnboarding] Caps Lock catalog configuration is invalid")
            return .failed
        }

        if let existing = manager.ruleCollections.first(where: {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }) {
            let quickLauncherInstalled = await PackInstaller.shared.isInstalled(
                packID: PackRegistry.launcher.id
            )
            if capsLockAlreadyProvidesFirstWin(
                existing: existing,
                quickLauncherInstalled: quickLauncherInstalled
            ) {
                return await verifyLiveRuleApplication(
                    using: viewModel,
                    alreadyConfigured: true
                )
            }

            if existing.isEnabled,
               existing.configuration == configuration,
               await PackInstaller.shared.isInstalled(packID: PackRegistry.capsLockToEscape.id)
            {
                return await verifyLiveRuleApplication(
                    using: viewModel,
                    alreadyConfigured: true
                )
            }

            if capsLockRequiresRulesHandoff(
                existing: existing,
                catalogConfiguration: catalogConfiguration,
                onboardingConfiguration: configuration
            ) {
                AppLogger.shared.log(
                    "🛡️ [FirstSuccessOnboarding] Existing Caps Lock behavior left untouched"
                )
                return .needsRules
            }
        }

        if onboardingConfigurationConflicts(
            manager: manager,
            collectionID: RuleCollectionIdentifier.capsLockRemap,
            configuration: configuration
        ) {
            AppLogger.shared.log(
                "🛡️ [FirstSuccessOnboarding] Caps Lock conflicts with an existing rule; leaving it untouched"
            )
            return .needsRules
        }

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.capsLockToEscape,
                collectionConfiguration: configuration,
                autoResolveCollectionConflicts: false,
                manager: manager,
                skipFinalReload: true
            )
        } catch {
            AppLogger.shared.error("❌ [FirstSuccessOnboarding] Could not install Caps Lock Remap: \(error)")
            return .failed
        }

        guard let capsLock = manager.ruleCollections.first(where: {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }) else {
            return .failed
        }

        let installed = capsLock.isEnabled
            && capsLock.configuration.tapHoldPickerConfig?.selectedTapOutput == "esc"
            && capsLock.configuration.tapHoldPickerConfig?.selectedHoldOutput == "caps"
        guard installed else { return .failed }
        return await verifyLiveRuleApplication(using: viewModel)
    }

    static func capsLockRequiresRulesHandoff(
        existing: RuleCollection,
        catalogConfiguration: RuleCollectionConfiguration,
        onboardingConfiguration: RuleCollectionConfiguration
    ) -> Bool {
        existing.configuration != catalogConfiguration
            && existing.configuration != onboardingConfiguration
    }

    static func capsLockRequiresHyperRulesHandoff(
        existing: RuleCollection,
        catalogConfiguration: RuleCollectionConfiguration,
        escapeConfiguration: RuleCollectionConfiguration,
        hyperConfiguration: RuleCollectionConfiguration
    ) -> Bool {
        existing.configuration != catalogConfiguration
            && existing.configuration != escapeConfiguration
            && existing.configuration != hyperConfiguration
    }

    static func capsLockAlreadyProvidesFirstWin(
        existing: RuleCollection,
        quickLauncherInstalled: Bool
    ) -> Bool {
        guard quickLauncherInstalled,
              existing.isEnabled,
              let tapHold = existing.configuration.tapHoldPickerConfig
        else {
            return false
        }

        return tapHold.selectedTapOutput == "esc"
            && tapHold.selectedHoldOutput == "hyper"
    }

    static func escapeOnlyCapsLockConfiguration(
        from configuration: RuleCollectionConfiguration
    ) -> RuleCollectionConfiguration? {
        guard let tapHold = configuration.tapHoldPickerConfig else { return nil }

        var holdOptions = tapHold.holdOptions
        if !holdOptions.contains(where: { $0.output == "caps" }) {
            holdOptions.append(SingleKeyPreset(
                output: "caps",
                label: "⇪ Caps Lock",
                description: "Keep the original Caps Lock action when the key is held",
                icon: "capslock"
            ))
        }

        return .tapHoldPicker(TapHoldPickerConfig(
            inputKey: tapHold.inputKey,
            tapOptions: tapHold.tapOptions,
            holdOptions: holdOptions,
            selectedTapOutput: "esc",
            selectedHoldOutput: "caps"
        ))
    }

    private static func installQuickLauncher(
        using viewModel: KanataViewModel
    ) async -> FirstSuccessOnboardingSession.ActionResult {
        let manager = viewModel.underlyingManager.rulesManager

        guard let catalogConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
            .configuration,
            let emptyConfiguration = emptyQuickLauncherConfiguration(
                from: catalogConfiguration
            )
        else {
            AppLogger.shared.error(
                "❌ [FirstSuccessOnboarding] Quick Launcher catalog configuration is unavailable"
            )
            return .failed
        }

        let existingLauncher = manager.ruleCollections.first(where: {
            $0.id == RuleCollectionIdentifier.launcher
        })
        // An untouched catalog collection can already be enabled and contain
        // example mappings. Onboarding starts that managed state empty so the
        // first shortcut is genuinely the person's choice. A customized
        // launcher remains byte-for-byte intact only when it already uses the
        // Hyper-hold gesture this lesson teaches.
        let shouldPreserveExistingLauncher = existingLauncher.map {
            shouldPreserveLauncherConfiguration(
                existing: $0,
                catalogConfiguration: catalogConfiguration
            )
        } ?? false
        let customizedLauncherBlocksTaughtGesture = existingLauncher.map {
            customizedLauncherBlocksTaughtHyperGesture(
                existing: $0,
                catalogConfiguration: catalogConfiguration
            )
        } ?? false

        if customizedLauncherBlocksTaughtGesture {
            AppLogger.shared.log(
                "🛡️ [FirstSuccessOnboarding] Existing Quick Launcher activation left untouched"
            )
            return .needsRules
        }

        if await PackInstaller.shared.isInstalled(packID: PackRegistry.launcher.id) {
            guard await quickLauncherIsReady(using: viewModel) else { return .needsRules }

            if shouldPreserveExistingLauncher {
                return await verifyLiveRuleApplication(
                    using: viewModel,
                    alreadyConfigured: true
                )
            }

            guard let freshLauncher = emptyConfiguration.launcherGridConfig else {
                return .failed
            }
            let saved = await manager.applyLauncherConfig(
                id: RuleCollectionIdentifier.launcher,
                config: freshLauncher,
                skipReload: true
            )
            guard saved,
                  manager.ruleCollections.first(where: {
                      $0.id == RuleCollectionIdentifier.launcher
                  })?.configuration.launcherGridConfig == freshLauncher
            else {
                return .failed
            }
            return await verifyLiveRuleApplication(using: viewModel)
        }
        let launcherConfiguration = shouldPreserveExistingLauncher
            ? existingLauncher?.configuration ?? emptyConfiguration
            : emptyConfiguration

        guard let capsCatalogConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })?
            .configuration,
            let escapeConfiguration = escapeOnlyCapsLockConfiguration(
                from: capsCatalogConfiguration
            ),
            let hyperConfiguration = PackRegistry.launcher.managedDefaults
            .first(where: { $0.collectionID == RuleCollectionIdentifier.capsLockRemap })?
            .defaultConfiguration
        else {
            AppLogger.shared.error(
                "❌ [FirstSuccessOnboarding] Quick Launcher Hyper configuration is unavailable"
            )
            return .failed
        }

        if let capsLock = manager.ruleCollections.first(where: {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }) {
            if capsLockRequiresHyperRulesHandoff(
                existing: capsLock,
                catalogConfiguration: capsCatalogConfiguration,
                escapeConfiguration: escapeConfiguration,
                hyperConfiguration: hyperConfiguration
            ) {
                AppLogger.shared.log(
                    "🛡️ [FirstSuccessOnboarding] Existing Caps Lock hold behavior left untouched"
                )
                return .needsRules
            }
        }

        if onboardingConfigurationConflicts(
            manager: manager,
            collectionID: RuleCollectionIdentifier.capsLockRemap,
            configuration: hyperConfiguration
        ) || onboardingConfigurationConflicts(
            manager: manager,
            collectionID: RuleCollectionIdentifier.launcher,
            configuration: launcherConfiguration
        ) {
            AppLogger.shared.log(
                "🛡️ [FirstSuccessOnboarding] Quick Launcher conflicts with an existing rule; leaving it untouched"
            )
            return .needsRules
        }

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.launcher,
                collectionConfiguration: launcherConfiguration,
                managedDefaultPolicy: .useRecommended,
                manager: manager,
                skipFinalReload: true
            )
        } catch {
            AppLogger.shared.error("❌ [FirstSuccessOnboarding] Could not install Quick Launcher: \(error)")
            return .failed
        }

        guard await quickLauncherIsReady(using: viewModel),
              manager.ruleCollections.first(where: {
                  $0.id == RuleCollectionIdentifier.launcher
              })?.configuration == launcherConfiguration
        else {
            return .failed
        }
        return await verifyLiveRuleApplication(using: viewModel)
    }

    static func emptyQuickLauncherConfiguration(
        from configuration: RuleCollectionConfiguration
    ) -> RuleCollectionConfiguration? {
        guard var launcher = configuration.launcherGridConfig else { return nil }
        launcher.activationMode = .holdHyper
        launcher.hyperTriggerMode = .hold
        launcher.mappings = []
        return .launcherGrid(launcher)
    }

    static func shouldPreserveLauncherConfiguration(
        existing: RuleCollection,
        catalogConfiguration: RuleCollectionConfiguration
    ) -> Bool {
        existing.configuration != catalogConfiguration
    }

    static func occupiedLauncherKeys(
        existing: RuleCollection?,
        catalogConfiguration: RuleCollectionConfiguration?
    ) -> Set<String> {
        guard let existing else { return [] }
        let shouldPreserve = catalogConfiguration.map {
            shouldPreserveLauncherConfiguration(
                existing: existing,
                catalogConfiguration: $0
            )
        } ?? true
        guard shouldPreserve else { return [] }
        return Set(existing.configuration.launcherGridConfig?.mappings.map(\.key) ?? [])
    }

    static func launcherUsesTaughtHyperGesture(
        _ configuration: RuleCollectionConfiguration
    ) -> Bool {
        guard let launcher = configuration.launcherGridConfig else { return false }
        return launcher.activationMode == .holdHyper
            && launcher.hyperTriggerMode == .hold
    }

    static func customizedLauncherBlocksTaughtHyperGesture(
        existing: RuleCollection,
        catalogConfiguration: RuleCollectionConfiguration
    ) -> Bool {
        shouldPreserveLauncherConfiguration(
            existing: existing,
            catalogConfiguration: catalogConfiguration
        ) && !launcherUsesTaughtHyperGesture(existing.configuration)
    }

    static func launcherConfiguration(
        appending mapping: LauncherMapping,
        to configuration: RuleCollectionConfiguration
    ) -> LauncherGridConfig? {
        guard var launcher = configuration.launcherGridConfig else { return nil }
        let normalizedKey = LauncherGridConfig.normalizeKey(mapping.key)
        guard LauncherGridConfig.isValidKey(normalizedKey),
              !launcher.mappings.contains(where: {
                  $0.id != mapping.id
                      && LauncherGridConfig.normalizeKey($0.key) == normalizedKey
              })
        else {
            return nil
        }

        var normalizedMapping = mapping
        normalizedMapping.key = normalizedKey
        if let existingIndex = launcher.mappings.firstIndex(where: { $0.id == mapping.id }) {
            launcher.mappings[existingIndex] = normalizedMapping
        } else {
            launcher.mappings.append(normalizedMapping)
        }
        launcher.hasSeenWelcome = true
        return launcher
    }

    private static func saveLauncherShortcut(
        _ mapping: LauncherMapping,
        using viewModel: KanataViewModel
    ) async -> FirstSuccessOnboardingSession.ActionResult {
        let manager = viewModel.underlyingManager.rulesManager
        guard await quickLauncherIsReady(using: viewModel),
              let launcherIndex = manager.ruleCollections.firstIndex(where: {
                  $0.id == RuleCollectionIdentifier.launcher
              })
        else {
            return .failed
        }

        let currentCollection = manager.ruleCollections[launcherIndex]
        let normalizedKey = LauncherGridConfig.normalizeKey(mapping.key)
        let existingMappings = currentCollection.configuration.launcherGridConfig?.mappings ?? []
        if let existingMapping = existingMappings.first(where: { $0.id == mapping.id }),
           LauncherGridConfig.normalizeKey(existingMapping.key) == normalizedKey,
           existingMapping.action == mapping.action,
           existingMapping.isEnabled
        {
            return await verifyLiveRuleApplication(
                using: viewModel,
                alreadyConfigured: true
            )
        }

        if let existingMapping = existingMappings.first(where: {
            $0.id != mapping.id
                && LauncherGridConfig.normalizeKey($0.key) == normalizedKey
        }) {
            guard existingMapping.action == mapping.action,
                  existingMapping.isEnabled
            else {
                return .needsRules
            }
            return await verifyLiveRuleApplication(
                using: viewModel,
                alreadyConfigured: true
            )
        }

        guard let desiredConfiguration = launcherConfiguration(
            appending: mapping,
            to: currentCollection.configuration
        ) else {
            return .failed
        }

        var candidate = currentCollection
        candidate.configuration = .launcherGrid(desiredConfiguration)
        candidate.isEnabled = true
        if manager.conflictInfo(for: candidate) != nil {
            AppLogger.shared.log(
                "🛡️ [FirstSuccessOnboarding] Selected launcher key conflicts with an existing rule"
            )
            return .needsRules
        }

        let saved = await manager.applyLauncherConfig(
            id: RuleCollectionIdentifier.launcher,
            config: desiredConfiguration,
            skipReload: true
        )
        guard saved,
              manager.ruleCollections.first(where: {
                  $0.id == RuleCollectionIdentifier.launcher
              })?.configuration.launcherGridConfig == desiredConfiguration
        else {
            return .failed
        }

        return await verifyLiveRuleApplication(using: viewModel)
    }

    static func onboardingConfigurationConflicts(
        manager: RuleCollectionsManager,
        collectionID: UUID,
        configuration: RuleCollectionConfiguration
    ) -> Bool {
        let catalogCollection = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == collectionID })
        guard var candidate = manager.ruleCollections.first(where: {
            $0.id == collectionID
        }) ?? catalogCollection else {
            return true
        }

        candidate.isEnabled = true
        candidate.configuration = configuration
        return manager.conflictInfo(for: candidate) != nil
    }

    static func onboardingActionResult(
        for disposition: ReloadDisposition,
        alreadyConfigured: Bool = false
    ) -> FirstSuccessOnboardingSession.ActionResult {
        guard disposition == .applied else { return .savedButNotActive }
        return alreadyConfigured ? .alreadyConfigured : .applied
    }

    private static func verifyLiveRuleApplication(
        using viewModel: KanataViewModel,
        alreadyConfigured: Bool = false
    ) async -> FirstSuccessOnboardingSession.ActionResult {
        let result = await viewModel.underlyingManager.applyPersistedRuleChanges()
        return onboardingActionResult(
            for: result.disposition,
            alreadyConfigured: alreadyConfigured
        )
    }

    private static func quickLauncherIsReady(using viewModel: KanataViewModel) async -> Bool {
        let manager = viewModel.underlyingManager.rulesManager
        guard await PackInstaller.shared.isInstalled(packID: PackRegistry.launcher.id),
              let capsLock = manager.ruleCollections.first(where: {
                  $0.id == RuleCollectionIdentifier.capsLockRemap
              }),
              let launcher = manager.ruleCollections.first(where: {
                  $0.id == RuleCollectionIdentifier.launcher
              })
        else {
            return false
        }

        return capsLock.isEnabled
            && capsLock.configuration.tapHoldPickerConfig?.selectedTapOutput == "esc"
            && capsLock.configuration.tapHoldPickerConfig?.selectedHoldOutput == "hyper"
            && launcher.isEnabled
            && launcherUsesTaughtHyperGesture(launcher.configuration)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FirstSuccessOnboardingWindowController: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        guard actionCoordinator.canDismiss else {
            NSSound.beep()
            return false
        }
        return true
    }

    func windowWillClose(_: Notification) {
        LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
        Self.currentController = nil
    }
}

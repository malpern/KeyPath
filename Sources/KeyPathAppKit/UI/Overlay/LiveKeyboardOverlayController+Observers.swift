import AppKit
import Foundation
import KeyPathCore
import SwiftUI

extension LiveKeyboardOverlayController {
    // MARK: - Notification Observers

    func setupOpenOverlayWithMapperObserver() {
        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.openOverlayWithMapper,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (_: Foundation.Notification) in
            Task { @MainActor in
                self?.openWithMapperTab()
            }
        }

        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.openOverlayWithMapperPreset,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (notification: Foundation.Notification) in
            let inputKey = notification.userInfo?["inputKey"] as? String
            let outputKey = notification.userInfo?["outputKey"] as? String
            let shiftedOutputKey = notification.userInfo?["shiftedOutputKey"] as? String
            let appBundleId = notification.userInfo?["appBundleId"] as? String
            let appDisplayName = notification.userInfo?["appDisplayName"] as? String
            Task { @MainActor in
                self?.openWithMapperTabAndPreset(
                    inputKey: inputKey,
                    outputKey: outputKey,
                    shiftedOutputKey: shiftedOutputKey,
                    appBundleId: appBundleId,
                    appDisplayName: appDisplayName
                )
            }
        }
    }

    @MainActor
    func openWithMapperTab() {
        for window in NSApp.windows where window.title == "KeyPath Settings" {
            window.close()
        }

        showResetCentered()
        openInspector(animated: true)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.1,
            execute: DispatchWorkItem {
                Foundation.NotificationCenter.default.post(
                    name: Foundation.Notification.Name.switchToMapperTab,
                    object: nil
                )
            }
        )
    }

    @MainActor
    func openWithMapperTabAndPreset(
        inputKey: String?,
        outputKey: String?,
        shiftedOutputKey: String?,
        appBundleId: String?,
        appDisplayName: String?
    ) {
        for window in NSApp.windows where window.title == "KeyPath Settings" {
            window.close()
        }

        showResetCentered()
        openInspector(animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: DispatchWorkItem {
            var notificationUserInfo: [String: Any] = [:]
            if let inputKey {
                notificationUserInfo["inputKey"] = inputKey
            }
            if let outputKey {
                notificationUserInfo["outputKey"] = outputKey
            }
            if let shiftedOutputKey {
                notificationUserInfo["shiftedOutputKey"] = shiftedOutputKey
            }
            if let appBundleId {
                notificationUserInfo["appBundleId"] = appBundleId
            }
            if let appDisplayName {
                notificationUserInfo["appDisplayName"] = appDisplayName
            }
            Foundation.NotificationCenter.default.post(
                name: Foundation.Notification.Name.switchToMapperTab,
                object: nil,
                userInfo: notificationUserInfo.isEmpty ? nil : notificationUserInfo
            )
        })
    }

    static func resolveAccessibilityTestMode() -> Bool {
        let envVar = ProcessInfo.processInfo.environment["KEYPATH_ACCESSIBILITY_TEST_MODE"] != nil
        let prefValue = PreferencesService.shared.accessibilityTestMode
        let hasExplicitPref = UserDefaults.standard.object(forKey: "KeyPath.Testing.AccessibilityTestMode") != nil
        if hasExplicitPref {
            return prefValue
        }
        return envVar || prefValue
    }

    func setupWizardVisibilityObserver() {
        Foundation.NotificationCenter.default.addObserver(
            forName: .wizardOpened,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let window = self.window, window.isVisible else { return }
                self.overlayHiddenByWizard = true
                window.orderOut(nil)
                AppLogger.shared.log("🪟 [OverlayController] Hidden overlay — wizard opened")
            }
        }

        Foundation.NotificationCenter.default.addObserver(
            forName: .wizardClosed,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.overlayHiddenByWizard else { return }
                self.overlayHiddenByWizard = false
                self.window?.orderFront(nil)
                AppLogger.shared.log("🪟 [OverlayController] Restored overlay — wizard closed")
            }
        }
    }

    func setupAccessibilityTestModeObserver() {
        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.accessibilityTestModeChanged,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (_: Foundation.Notification) in
            Task { @MainActor in
                self?.recreateWindowForTestModeChange()
            }
        }
    }

    func recreateWindowForTestModeChange() {
        let wasVisible = window?.isVisible ?? false
        let savedFrame = window?.frame

        viewModel.stopCapturing()
        dismissHintBubble()
        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            closeInspector(animated: false)
        }
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
        hostingView = nil

        guard wasVisible else {
            AppLogger.shared.log("🪟 [OverlayController] Test mode changed - window was hidden, will recreate on next show")
            return
        }

        createWindow()
        if let savedFrame, let window {
            window.setFrame(savedFrame, display: true)
        }
        viewModel.startCapturing()
        viewModel.noteInteraction()
        window?.orderFront(nil)

        let mode = PreferencesService.shared.accessibilityTestMode ? "titled (test)" : "chromeless"
        AppLogger.shared.log("🪟 [OverlayController] Recreated overlay window as \(mode)")
    }

    func observeHealthState() {
        if healthObserver == nil {
            healthObserver = OverlayHealthIndicatorObserver(
                onStateChange: { [weak self] state in
                    self?.uiState.healthIndicatorState = state
                },
                onDismiss: { [weak self] in
                    withAnimation(.easeOut(duration: 0.3)) {
                        self?.uiState.healthIndicatorState = .dismissed
                    }
                }
            )
        }

        healthObserver?.startObserving(controller: MainAppStateController.shared)
    }

    func handleHealthIndicatorTap() {
        AppLogger.shared.log("🔘 [Controller] handleHealthIndicatorTap - bringing main window to front and opening wizard")

        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow = NSApp.windows.first(where: { !$0.styleMask.contains(.borderless) && $0.level == .normal }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }

        Foundation.NotificationCenter.default.post(
            name: Foundation.Notification.Name.showWizard,
            object: nil
        )

        withAnimation {
            uiState.healthIndicatorState = .dismissed
        }
    }
}

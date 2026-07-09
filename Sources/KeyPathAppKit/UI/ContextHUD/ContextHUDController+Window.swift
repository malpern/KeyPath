import AppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

// MARK: - Window Management, Launcher KeyMap & Cheat Sheet

extension ContextHUDController {
    func showWindow() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        if let hostingView {
            hostingView.rootView = ContextHUDView(viewModel: viewModel)
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
        }

        window.contentView?.alphaValue = 0

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            if let hostingView {
                hostingView.invalidateIntrinsicContentSize()
                hostingView.layoutSubtreeIfNeeded()
            }

            positionWindow()

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                let bounds = contentView.bounds
                contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

                contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
                contentView.alphaValue = 0

                window.orderFront(nil)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    contentView.animator().alphaValue = 1.0
                    contentView.layer?.transform = CATransform3DIdentity
                }
            } else {
                window.orderFront(nil)
            }

            AppLogger.shared.debug("🎯 [ContextHUD] Showing HUD for layer '\(viewModel.layerName)'")
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let window, window.isVisible else { return }

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                contentView.animator().alphaValue = 0
                contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            } completionHandler: {
                Task { @MainActor in
                    window.orderOut(nil)
                    contentView.alphaValue = 1.0
                    contentView.layer?.transform = CATransform3DIdentity
                }
            }
        } else {
            window.orderOut(nil)
        }

        AppLogger.shared.debug("🎯 [ContextHUD] Dismissed")
    }

    func scheduleDismiss() {
        dismissTask?.cancel()
        let timeout = PreferencesService.shared.contextHUDTimeout
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    // MARK: - Launcher KeyMap from Collections

    func buildLauncherKeyMap(from collections: [RuleCollection]) -> [UInt16: LayerKeyInfo] {
        guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
              let config = launcherCollection.configuration.launcherGridConfig
        else {
            return [:]
        }

        var keyMap: [UInt16: LayerKeyInfo] = [:]
        let collectionId = launcherCollection.id

        for mapping in config.mappings where mapping.isEnabled {
            guard let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(mapping.key) else {
                continue
            }

            let info: LayerKeyInfo = switch mapping.action {
            case let .launchApp(name, bundleId):
                .appLaunch(appIdentifier: bundleId ?? name, collectionId: collectionId)
            case let .openURL(urlString):
                .webURL(url: urlString, collectionId: collectionId)
            case .openFolder, .runScript:
                .pushMsg(message: mapping.action.displayName, collectionId: collectionId)
            default:
                .pushMsg(message: mapping.action.displayName, collectionId: collectionId)
            }

            keyMap[keyCode] = info
        }

        return keyMap
    }

    func preloadLauncherIcons(keyMap: [UInt16: LayerKeyInfo]) async {
        await withTaskGroup(of: Void.self) { group in
            for (_, info) in keyMap {
                if let appId = info.appLaunchIdentifier {
                    _ = IconResolverService.shared.resolveAppIcon(for: appId)
                }
                if let url = info.urlIdentifier {
                    group.addTask {
                        await IconResolverService.shared.preloadIcon(for: .url(url))
                    }
                }
            }
        }
    }

    // MARK: - Window Creation & Positioning

    func createWindow() {
        let hudView = ContextHUDView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: hudView)
        hosting.setFrameSize(NSSize(width: 400, height: 240))

        let newWindow = ContextHUDWindow(contentView: hosting)
        hostingView = hosting
        window = newWindow
    }

    func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame

        if let hostingView {
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()

            let fittingSize = hostingView.fittingSize
            let horizontalMargin: CGFloat = 64
            let verticalMargin: CGFloat = 80
            let maxWidth = max(600, screenFrame.width - horizontalMargin)
            let maxHeight = max(400, screenFrame.height - verticalMargin)
            let width = min(max(fittingSize.width, 240), maxWidth)
            let height = min(max(fittingSize.height, 100), maxHeight)
            window.setContentSize(NSSize(width: width, height: height))
        }

        let windowFrame = window.frame
        let x = screenFrame.midX - (windowFrame.width / 2)
        let y = screenFrame.midY - (windowFrame.height / 2)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Backtick Cheat Sheet

    func startBacktickMonitor() {
        backtickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleBacktickCandidate(event)
            }
        }
    }

    func handleBacktickCandidate(_ event: NSEvent) {
        guard !cheatSheetVisible,
              kindaVimPackInstalled,
              event.charactersIgnoringModifiers == "`",
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              KindaVimStateAdapter.shared.state.mode == .normal
        else { return }

        showKindaVimCheatSheet()
    }

    func showKindaVimCheatSheet() {
        cheatSheetVisible = true

        if !hasStartedKindaVimStateMonitoring {
            kindaVimStateAdapter.startMonitoring()
            hasStartedKindaVimStateMonitoring = true
        }

        viewModel.update(
            layerName: "nav",
            keyMap: [:],
            collections: [],
            style: .kindaVimLearning,
            holdLabels: [:],
            launcherKeyMap: [:],
            kindaVimState: kindaVimStateAdapter.state,
            kindaVimLeaderHUDMode: .cheatSheetOnly
        )

        showWindow()
        installCheatSheetDismissMonitors()
    }

    func installCheatSheetDismissMonitors() {
        cheatSheetDismissKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor in
                self?.dismissCheatSheet()
            }
        }
        cheatSheetDismissClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissCheatSheet()
            }
        }
    }

    func dismissCheatSheet() {
        guard cheatSheetVisible else { return }
        cheatSheetVisible = false

        if let m = cheatSheetDismissKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = cheatSheetDismissClickMonitor { NSEvent.removeMonitor(m) }
        cheatSheetDismissKeyMonitor = nil
        cheatSheetDismissClickMonitor = nil

        dismiss()
    }
}

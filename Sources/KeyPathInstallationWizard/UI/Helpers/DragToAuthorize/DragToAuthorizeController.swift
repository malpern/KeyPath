import AppKit
import KeyPathCore
import KeyPathPermissions
import SwiftUI

/// Orchestrates the drag-to-authorize overlay lifecycle.
/// Manages panel presentation, Settings window tracking, permission polling,
/// and state transitions with animations.
@MainActor
public final class DragToAuthorizeController: ObservableObject {
    public static let shared = DragToAuthorizeController()

    // MARK: - Public Types

    public enum PermissionTarget: Sendable {
        case accessibility
        case inputMonitoring
        case fullDiskAccess

        var settingsURL: URL {
            switch self {
            case .accessibility:
                URL(string: KeyPathConstants.URLs.accessibilityPrivacy)!
            case .inputMonitoring:
                URL(string: KeyPathConstants.URLs.inputMonitoringPrivacy)!
            case .fullDiskAccess:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            }
        }

        var displayName: String {
            switch self {
            case .accessibility: "Accessibility"
            case .inputMonitoring: "Input Monitoring"
            case .fullDiskAccess: "Full Disk Access"
            }
        }
    }

    public enum OverlayState: Equatable {
        case idle
        case presenting
        case visible
        case dragging
        case success
        case retrying
        case dismissing
    }

    // MARK: - Published State

    @Published public private(set) var state: OverlayState = .idle
    @Published public private(set) var currentTarget: PermissionTarget?

    // MARK: - Private Properties

    private var panel: DragToAuthorizePanel?
    private var tracker: SettingsWindowTracker?
    private var stateModel: DragToAuthorizeStateModel?
    private var permissionPollTimer: Timer?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Public API

    /// Present the drag-to-authorize overlay for the given permission target.
    /// Opens System Settings and shows the floating panel anchored below it.
    public func present(for target: PermissionTarget, sourceRect: NSRect? = nil, in sourceWindow: NSWindow? = nil) {
        guard state == .idle else {
            dismiss(animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.present(for: target, sourceRect: sourceRect, in: sourceWindow)
            }
            return
        }

        currentTarget = target
        state = .presenting

        NSWorkspace.shared.open(target.settingsURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.createAndShowPanel(for: target, sourceRect: sourceRect, sourceWindow: sourceWindow)
        }

        AppLogger.shared.log("🎯 [DragToAuthorize] Presenting for \(target.displayName)")
    }

    /// Dismiss the overlay with optional animation.
    public func dismiss(animated: Bool = true) {
        guard state != .idle else { return }

        dismissWorkItem?.cancel()
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        tracker?.stopTracking()
        tracker = nil

        if animated {
            state = .dismissing
            stateModel?.transitionTo(.dismissing)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.tearDown()
            }
        } else {
            tearDown()
        }
    }

    // MARK: - Internal Callbacks (from drag source)

    func dragDidBegin() {
        state = .dragging
        stateModel?.transitionTo(.dragging)
        AppLogger.shared.log("🎯 [DragToAuthorize] Drag began")
    }

    func dragDidEnd(accepted: Bool) {
        if accepted {
            transitionToSuccess()
        } else {
            state = .retrying
            stateModel?.transitionTo(.retrying)
            AppLogger.shared.log("❌ [DragToAuthorize] Drop rejected — showing retry")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard self?.state == .retrying else { return }
                self?.state = .visible
                self?.stateModel?.transitionTo(.visible)
            }
        }
    }

    /// Called by permission polling when the target permission is granted.
    func permissionGrantDetected() {
        guard state == .visible || state == .dragging || state == .retrying else { return }
        transitionToSuccess()
    }

    // MARK: - Private Implementation

    private func createAndShowPanel(for target: PermissionTarget, sourceRect: NSRect?, sourceWindow: NSWindow?) {
        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 170

        let newPanel = DragToAuthorizePanel(contentRect: NSRect(
            x: 0, y: 0, width: panelWidth, height: panelHeight
        ))

        let model = DragToAuthorizeStateModel(target: target, controller: self)
        stateModel = model

        let overlayView = DragToAuthorizeOverlayView(model: model)
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]

        // Embed drag source on top of the tile area
        let launcherPath = WizardSystemPaths.bundledKanataLauncherPath
        let launcherURL = URL(fileURLWithPath: launcherPath)
        let dragSource = DragToAuthorizeDragSource(fileURL: launcherURL, frame: NSRect(
            x: 24, y: 16, width: panelWidth - 48, height: 52
        ))
        dragSource.onDragBegan = { [weak self] in
            self?.dragDidBegin()
        }
        dragSource.onDragEnded = { [weak self] operation in
            self?.dragDidEnd(accepted: operation != [])
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.wantsLayer = true
        container.addSubview(hosting)
        container.addSubview(dragSource)

        newPanel.contentView = container

        // Start with panel invisible for animation
        newPanel.alphaValue = 0
        panel = newPanel

        // Start tracking Settings window
        let newTracker = SettingsWindowTracker()
        newTracker.onFrameUpdate = { [weak self, weak newPanel] settingsFrame in
            guard let panel = newPanel else { return }
            let x = settingsFrame.midX - panelWidth / 2
            let y = settingsFrame.minY - panelHeight - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))

            if !panel.isVisible {
                panel.orderFront(nil)
                self?.animatePresentation(panel: panel, sourceRect: sourceRect, sourceWindow: sourceWindow)
            }
        }
        newTracker.onWindowDisappeared = { [weak self] in
            AppLogger.shared.log("⚠️ [DragToAuthorize] Settings window disappeared")
            self?.dismiss(animated: true)
        }
        newTracker.startTracking()
        tracker = newTracker

        startPermissionPolling(for: target)
    }

    private func animatePresentation(panel: DragToAuthorizePanel, sourceRect: NSRect?, sourceWindow: NSWindow?) {
        if let sourceRect, let sourceWindow {
            // Animate from source rect (wizard button)
            let screenSourceRect = sourceWindow.convertToScreen(sourceRect)
            let finalFrame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screenSourceRect.midX - finalFrame.width / 2,
                y: screenSourceRect.midY - finalFrame.height / 2
            ))
            panel.alphaValue = 0.3

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
                panel.animator().setFrameOrigin(finalFrame.origin)
                panel.animator().alphaValue = 1.0
            } completionHandler: { [weak self] in
                self?.state = .visible
                self?.stateModel?.transitionTo(.visible)
            }
        } else {
            // Simple fade + slide up
            let finalOrigin = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y - 20))

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(finalOrigin)
                panel.animator().alphaValue = 1.0
            } completionHandler: { [weak self] in
                self?.state = .visible
                self?.stateModel?.transitionTo(.visible)
            }
        }
    }

    private func transitionToSuccess() {
        state = .success
        stateModel?.transitionTo(.success)
        AppLogger.shared.log("✅ [DragToAuthorize] Permission granted!")

        dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.dismiss(animated: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: dismissWorkItem!)
    }

    private func startPermissionPolling(for target: PermissionTarget) {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkPermission(for: target)
            }
        }
    }

    private func checkPermission(for target: PermissionTarget) async {
        let snapshot = await PermissionOracle.shared.forceRefresh()

        let granted: Bool = switch target {
        case .accessibility:
            snapshot.kanata.accessibility == .granted
        case .inputMonitoring:
            snapshot.kanata.inputMonitoring == .granted
        case .fullDiskAccess:
            // FDA doesn't exist in PermissionSet — skip polling for it
            false
        }

        if granted {
            permissionGrantDetected()
        }
    }

    private func tearDown() {
        panel?.orderOut(nil)
        panel = nil
        stateModel = nil
        currentTarget = nil
        state = .idle
    }
}

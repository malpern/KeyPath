import AppKit
import Combine
import KeyPathCore
import SwiftUI

/// Floating window that displays keyboard visualization
@MainActor
class KeyboardVisualizationWindow: NSWindow {
    private let viewModel: KeyboardVisualizationViewModel

    init() {
        let viewModel = KeyboardVisualizationViewModel()
        self.viewModel = viewModel

        // Calculate initial window size based on layout aspect ratio
        let layout = viewModel.layout
        let aspectRatio = layout.totalWidth / layout.totalHeight
        let defaultHeight: CGFloat = 300
        let defaultWidth = defaultHeight * aspectRatio

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth + 32, height: defaultHeight + 32),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = true
        isMovableByWindowBackground = true
        hasShadow = true

        // Position at center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - (defaultWidth + 32) / 2
            let y = screenFrame.midY - (defaultHeight + 32) / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Set content view with SwiftUI
        contentView = NSHostingView(rootView: KeyboardView(viewModel: viewModel))
    }

    func show() {
        viewModel.startCapturing()
        alphaValue = 1.0
        orderFront(nil)
        AppLogger.shared.log("⌨️ [KeyboardViz] Window shown")
    }

    func hide() {
        viewModel.stopCapturing()
        orderOut(nil)
        AppLogger.shared.log("⌨️ [KeyboardViz] Window hidden")
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
}

import Combine

/// Manager for the keyboard visualization window
@MainActor
class KeyboardVisualizationManager: ObservableObject {
    static let shared = KeyboardVisualizationManager()

    private var window: KeyboardVisualizationWindow?
    private var stateController: MainAppStateController?
    private var cancellables = Set<AnyCancellable>()
    private var wasVisibleBeforeStateChange = false

    private init() {
        // Observe system state changes
        observeSystemState()
    }

    func show() {
        // Check if system is green before showing
        if let stateController = stateController,
           let validationState = stateController.validationState,
           !validationState.isSuccess {
            // System is not green - show toast and don't show window
            UserFeedbackService.show(
                message: "Keyboard visualization requires KeyPath to be fully configured. Please complete setup first."
            )
            AppLogger.shared.warn("⌨️ [KeyboardViz] Cannot show - system not green")
            return
        }

        if window == nil {
            window = KeyboardVisualizationWindow()
        }
        wasVisibleBeforeStateChange = true
        window?.show()
    }

    func hide() {
        wasVisibleBeforeStateChange = false
        window?.hide()
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Update the state controller reference (called when MainAppStateController is available)
    func setStateController(_ stateController: MainAppStateController) {
        self.stateController = stateController
        observeSystemState()
    }

    // MARK: - System State Observation

    private func observeSystemState() {
        guard let stateController = stateController else {
            return
        }

        // Observe validation state changes
        stateController.$validationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] validationState in
                self?.handleStateChange(validationState: validationState)
            }
            .store(in: &cancellables)

        // Initial state check
        handleStateChange(validationState: stateController.validationState)
    }

    private func handleStateChange(validationState: MainAppStateController.ValidationState?) {
        let isGreen: Bool
        if let state = validationState {
            isGreen = state.isSuccess
        } else {
            // Not yet validated - treat as not green
            isGreen = false
        }

        // If system goes red and window is visible, close it and show toast
        if !isGreen, let window = window, window.isVisible {
            wasVisibleBeforeStateChange = true
            hide()
            UserFeedbackService.show(
                message: "Keyboard visualization disabled - KeyPath needs to be configured. Please complete setup."
            )
            AppLogger.shared.info("⌨️ [KeyboardViz] Window closed - system state changed to red")
        }
    }
}


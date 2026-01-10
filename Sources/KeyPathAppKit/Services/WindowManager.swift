import AppKit
import ApplicationServices
import Foundation
import KeyPathCore

// MARK: - Window Position

/// Represents a target window position/size
public enum WindowPosition: String, CaseIterable {
    case left
    case right
    case maximize
    case center
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case nextDisplay = "next-display"
    case previousDisplay = "previous-display"
    case nextSpace = "next-space"
    case previousSpace = "previous-space"
    case undo

    /// All position values for help text
    static var allValues: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

// MARK: - Window Manager

/// Manages window positioning using the macOS Accessibility API.
///
/// Requires Accessibility permission (same as Kanata).
///
/// ## Space Movement
/// Uses private CoreGraphics Services (CGS) APIs for moving windows between Spaces.
/// These APIs are stable but undocumented. See `CGSPrivate.swift` for details.
///
/// ## References
/// - https://github.com/lwouis/alt-tab-macos (Space enumeration)
/// - https://github.com/ianyh/Amethyst (Window-to-space movement)
@MainActor
public final class WindowManager {
    // MARK: - Singleton

    public static let shared = WindowManager()

    // MARK: - Undo State

    /// Previous window frame for single-level undo
    private var previousFrame: CGRect?
    private var previousWindowRef: AXUIElement?

    /// Track if we've shown the Space API unavailable warning (once per session)
    private var hasShownSpaceAPIWarning = false

    /// Track retry attempts for CGS API initialization
    private var retryAttempts = 0
    private let maxRetryAttempts = 3

    /// Track if initialization is in progress to avoid concurrent retries
    private var isInitializing = false

    // MARK: - Initialization

    private init() {}

    // MARK: - API Status

    /// Whether Accessibility permission is granted.
    /// Window management requires this permission to control other app windows.
    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Whether Space movement features are available.
    /// Call this at startup to check and warn user if needed.
    public var isSpaceMovementAvailable: Bool {
        SpaceManager.shared.isAvailable
    }

    /// Initialize and check Space API availability with retry logic.
    /// Call this after app has fully launched (e.g., 2-3 seconds after startup).
    /// - Returns: true if APIs are available, false otherwise
    @discardableResult
    public func initializeWithRetry() async -> Bool {
        guard !isInitializing else {
            AppLogger.shared.log("⚠️ [WindowManager] Initialization already in progress")
            return isSpaceMovementAvailable
        }

        isInitializing = true
        defer { isInitializing = false }

        // Try immediate initialization first
        if SpaceManager.shared.isAvailable {
            AppLogger.shared.log("✅ [WindowManager] Space APIs available immediately")
            return true
        }

        AppLogger.shared.log("⚠️ [WindowManager] Space APIs unavailable at startup - starting retry sequence")

        // Retry with exponential backoff
        for attempt in 1 ... maxRetryAttempts {
            let delaySeconds = Double(attempt) // 1s, 2s, 3s
            AppLogger.shared.log("⏳ [WindowManager] Retry attempt \(attempt)/\(maxRetryAttempts) in \(delaySeconds)s")

            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            if SpaceManager.shared.retryInitialization() {
                AppLogger.shared.log("✅ [WindowManager] Space APIs available after \(attempt) retry attempt(s)")
                return true
            }
        }

        // All retries failed - show warning
        AppLogger.shared.log("❌ [WindowManager] Space APIs unavailable after \(maxRetryAttempts) retry attempts")
        showSpaceAPIUnavailableWarning()
        return false
    }

    /// Show one-time warning that Space APIs are unavailable
    private func showSpaceAPIUnavailableWarning() {
        guard !hasShownSpaceAPIWarning else { return }
        hasShownSpaceAPIWarning = true

        UserNotificationService.shared.notifyActionError(
            "Space Movement Unavailable: The required macOS APIs are not available. Window-to-Space shortcuts will not work. This may happen after a macOS update."
        )
    }

    // MARK: - Public API

    /// Move the focused window to the specified position
    /// - Parameter position: Target position
    /// - Returns: true if successful, false otherwise
    @discardableResult
    public func moveWindow(to position: WindowPosition) -> Bool {
        AppLogger.shared.log("🪟 [WindowManager] Moving window to: \(position.rawValue)")

        // Check Accessibility permission first
        guard hasAccessibilityPermission else {
            AppLogger.shared.log("❌ [WindowManager] Accessibility permission not granted")
            notifyAccessibilityPermissionRequired()
            return false
        }

        // Handle undo specially
        if position == .undo {
            let success = undoLastMove()
            if !success {
                notifyOperationFailed("No previous window position to restore")
            }
            return success
        }

        // Handle display switching
        if position == .nextDisplay {
            let success = moveToNextDisplay()
            if !success {
                notifyOperationFailed("Unable to move window to next display. Make sure multiple displays are connected and the window can be moved.")
            }
            return success
        }
        if position == .previousDisplay {
            let success = moveToPreviousDisplay()
            if !success {
                notifyOperationFailed("Unable to move window to previous display. Make sure multiple displays are connected and the window can be moved.")
            }
            return success
        }

        // Handle space switching
        if position == .nextSpace {
            let success = moveToNextSpace()
            if !success, !hasShownSpaceAPIWarning {
                // Space-specific error already shown in moveToNextSpace
            }
            return success
        }
        if position == .previousSpace {
            let success = moveToPreviousSpace()
            if !success, !hasShownSpaceAPIWarning {
                // Space-specific error already shown in moveToPreviousSpace
            }
            return success
        }

        // Get the focused window
        guard let (window, currentFrame) = getFocusedWindow() else {
            AppLogger.shared.log("⚠️ [WindowManager] No focused window found")
            notifyOperationFailed("No window is currently focused. Click on a window first.")
            return false
        }

        // Store current frame for undo (before moving)
        previousFrame = currentFrame
        previousWindowRef = window

        // Get the screen containing the window
        guard let screen = screenContaining(frame: currentFrame) else {
            AppLogger.shared.log("⚠️ [WindowManager] Could not determine screen for window")
            notifyOperationFailed("Unable to determine which display the window is on")
            return false
        }

        // Calculate target frame
        let visibleFrame = screen.visibleFrame
        let targetFrame = calculateFrame(for: position, in: visibleFrame, currentFrame: currentFrame)

        // Apply the new frame
        let success = setWindowFrame(window, frame: targetFrame)
        if !success {
            notifyOperationFailed("Unable to move window to \(position.rawValue). The window may not support resizing or moving.")
        }
        return success
    }

    /// Show user feedback when Accessibility permission is required
    private func notifyAccessibilityPermissionRequired() {
        let message = "Window Management requires Accessibility permission. Enable in System Settings > Privacy & Security > Accessibility, then restart KeyPath."
        AppLogger.shared.log("⚠️ [WindowManager] \(message)")
        UserNotificationService.shared.notifyActionError(message)
    }

    /// Show user feedback when a window operation fails
    private func notifyOperationFailed(_ message: String) {
        AppLogger.shared.log("⚠️ [WindowManager] Operation failed: \(message)")
        UserNotificationService.shared.notifyActionError(message)
    }

    // MARK: - Frame Calculations

    private func calculateFrame(for position: WindowPosition, in visibleFrame: CGRect, currentFrame: CGRect) -> CGRect {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height
        let halfWidth = width / 2
        let halfHeight = height / 2

        switch position {
        case .left:
            return CGRect(x: x, y: y, width: halfWidth, height: height)

        case .right:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: height)

        case .maximize:
            // If already maximized, restore to previous (toggle behavior)
            if isApproximatelyEqual(currentFrame, visibleFrame) {
                if let previous = previousFrame {
                    return previous
                }
            }
            return visibleFrame

        case .center:
            // Center the window at its current size
            let centerX = x + (width - currentFrame.width) / 2
            let centerY = y + (height - currentFrame.height) / 2
            return CGRect(x: centerX, y: centerY, width: currentFrame.width, height: currentFrame.height)

        case .topLeft:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .topRight:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .bottomLeft:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)

        case .bottomRight:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)

        case .nextDisplay, .previousDisplay, .nextSpace, .previousSpace, .undo:
            // Handled separately
            return currentFrame
        }
    }

    // MARK: - Space Movement

    private func moveToNextSpace() -> Bool {
        moveToSpace(direction: .next)
    }

    private func moveToPreviousSpace() -> Bool {
        moveToSpace(direction: .previous)
    }

    private enum SpaceDirection {
        case next, previous
    }

    private func moveToSpace(direction: SpaceDirection) -> Bool {
        // Check API availability first and show user-facing error if unavailable
        guard SpaceManager.shared.isAvailable else {
            AppLogger.shared.log("⚠️ [WindowManager] Space movement unavailable - CGS APIs not found")

            // Only show notification once per session to avoid spam
            if !hasShownSpaceAPIWarning {
                hasShownSpaceAPIWarning = true
                UserNotificationService.shared.notifyActionError(
                    "Space Movement Unavailable: The macOS APIs needed for this feature are not available. This may happen after a macOS update."
                )
            }
            return false
        }

        guard let windowID = SpaceManager.shared.getFrontmostWindowID() else {
            AppLogger.shared.log("⚠️ [WindowManager] No frontmost window for space switch")
            return false
        }

        let targetSpaceID: CGSSpaceID? = switch direction {
        case .next:
            SpaceManager.shared.nextSpaceID()
        case .previous:
            SpaceManager.shared.previousSpaceID()
        }

        guard let spaceID = targetSpaceID else {
            AppLogger.shared.log("⚠️ [WindowManager] Could not determine target space")
            return false
        }

        let success = SpaceManager.shared.moveWindow(windowID, to: spaceID)

        if success {
            // Also switch to that space so the user follows the window
            // Use keyboard shortcut: Ctrl+Arrow
            simulateSpaceSwitch(direction: direction)
        }

        return success
    }

    private func simulateSpaceSwitch(direction: SpaceDirection) {
        // Ctrl+Left or Ctrl+Right to switch spaces
        let keyCode: CGKeyCode = direction == .next ? 0x7C : 0x7B // Right : Left arrow

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskControl
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskControl
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Display Movement

    private func moveToNextDisplay() -> Bool {
        moveToDisplay(offset: 1)
    }

    private func moveToPreviousDisplay() -> Bool {
        moveToDisplay(offset: -1)
    }

    private func moveToDisplay(offset: Int) -> Bool {
        guard let (window, currentFrame) = getFocusedWindow() else {
            AppLogger.shared.log("⚠️ [WindowManager] No focused window for display switch")
            return false
        }

        let screens = NSScreen.screens
        guard screens.count > 1 else {
            AppLogger.shared.log("⚠️ [WindowManager] Only one display available")
            return false
        }

        // Find current screen index
        guard let currentScreen = screenContaining(frame: currentFrame),
              let currentIndex = screens.firstIndex(of: currentScreen)
        else {
            AppLogger.shared.log("⚠️ [WindowManager] Could not determine current screen")
            return false
        }

        // Calculate target screen index (wrap around)
        let targetIndex = (currentIndex + offset + screens.count) % screens.count
        let targetScreen = screens[targetIndex]

        // Store for undo
        previousFrame = currentFrame
        previousWindowRef = window

        // Calculate relative position on new screen
        let currentVisibleFrame = currentScreen.visibleFrame
        let targetVisibleFrame = targetScreen.visibleFrame

        // Calculate relative position (0-1) on current screen
        let relativeX = (currentFrame.origin.x - currentVisibleFrame.origin.x) / currentVisibleFrame.width
        let relativeY = (currentFrame.origin.y - currentVisibleFrame.origin.y) / currentVisibleFrame.height
        let relativeWidth = currentFrame.width / currentVisibleFrame.width
        let relativeHeight = currentFrame.height / currentVisibleFrame.height

        // Apply to target screen
        let targetFrame = CGRect(
            x: targetVisibleFrame.origin.x + relativeX * targetVisibleFrame.width,
            y: targetVisibleFrame.origin.y + relativeY * targetVisibleFrame.height,
            width: relativeWidth * targetVisibleFrame.width,
            height: relativeHeight * targetVisibleFrame.height
        )

        AppLogger.shared.log("🪟 [WindowManager] Moving to display \(targetIndex + 1) of \(screens.count)")
        return setWindowFrame(window, frame: targetFrame)
    }

    // MARK: - Undo

    private func undoLastMove() -> Bool {
        guard let previousFrame, let previousWindowRef else {
            AppLogger.shared.log("⚠️ [WindowManager] No previous position to restore")
            return false
        }

        AppLogger.shared.log("🪟 [WindowManager] Undoing last move")

        // Clear undo state (single-level)
        self.previousFrame = nil
        self.previousWindowRef = nil

        return setWindowFrame(previousWindowRef, frame: previousFrame)
    }

    // MARK: - Accessibility Helpers

    /// Get the currently focused window and its frame
    private func getFocusedWindow() -> (AXUIElement, CGRect)? {
        // Get frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Get focused window
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)

        guard windowResult == .success, let window = windowRef else {
            return nil
        }

        let axWindow = window as! AXUIElement

        // Get current position and size
        guard let position = getWindowPosition(axWindow),
              let size = getWindowSize(axWindow)
        else {
            return nil
        }

        // Convert to CGRect (note: AX uses top-left origin, we need to handle this)
        let frame = CGRect(origin: position, size: size)
        return (axWindow, frame)
    }

    private func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)

        guard result == .success, let positionValue = positionRef else {
            return nil
        }

        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        return position
    }

    private func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        guard result == .success, let sizeValue = sizeRef else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return size
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) -> Bool {
        // Set position
        var position = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }

        let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        // Set size
        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        let success = posResult == .success && sizeResult == .success

        if success {
            AppLogger.shared.log("✅ [WindowManager] Window moved to \(frame)")
        } else {
            AppLogger.shared.log("⚠️ [WindowManager] Failed to set window frame (pos: \(posResult.rawValue), size: \(sizeResult.rawValue))")
        }

        return success
    }

    // MARK: - Screen Helpers

    /// Find the screen that contains the majority of the given frame
    private func screenContaining(frame: CGRect) -> NSScreen? {
        // NSScreen uses bottom-left origin, AX uses top-left
        // We need to find which screen contains the window center

        let windowCenter = CGPoint(x: frame.midX, y: frame.midY)

        for screen in NSScreen.screens {
            // Convert AX coordinates (top-left origin) to screen coordinates
            // AX y=0 is at top of main screen, NSScreen y=0 is at bottom
            let screenFrame = screen.frame

            // Check if window center is within this screen's frame
            // Account for coordinate system differences
            if screenFrame.contains(windowCenter) ||
                isWindowOnScreen(frame: frame, screen: screen) {
                return screen
            }
        }

        // Fallback to main screen
        return NSScreen.main
    }

    /// Check if window overlaps significantly with a screen
    private func isWindowOnScreen(frame: CGRect, screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        let intersection = frame.intersection(screenFrame)

        // Window is on this screen if more than 50% of its area intersects
        let windowArea = frame.width * frame.height
        let intersectionArea = intersection.width * intersection.height

        return intersectionArea > windowArea * 0.5
    }

    /// Check if two frames are approximately equal (within 10px)
    private func isApproximatelyEqual(_ frame1: CGRect, _ frame2: CGRect, tolerance: CGFloat = 10) -> Bool {
        abs(frame1.origin.x - frame2.origin.x) < tolerance &&
            abs(frame1.origin.y - frame2.origin.y) < tolerance &&
            abs(frame1.width - frame2.width) < tolerance &&
            abs(frame1.height - frame2.height) < tolerance
    }
}

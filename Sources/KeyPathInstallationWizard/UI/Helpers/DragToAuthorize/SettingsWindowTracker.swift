import AppKit
import CoreGraphics

/// Tracks the System Settings window frame via CGWindowList polling.
/// Smooth interpolation prevents jumpy repositioning.
@MainActor
final class SettingsWindowTracker {
    var onFrameUpdate: (@MainActor (NSRect) -> Void)?
    var onWindowDisappeared: (@MainActor () -> Void)?

    private var timer: Timer?
    private var currentFrame: NSRect = .zero
    private var targetFrame: NSRect = .zero
    private var wasVisible = false
    private let lerpFactor: CGFloat = 0.3

    func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            handleDisappeared()
            return
        }

        let settingsWindow = windowList.first { info in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { return false }
            return ownerName == "System Settings" || ownerName == "System Preferences"
        }

        guard let window = settingsWindow,
              let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"]
        else {
            handleDisappeared()
            return
        }

        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let frame = NSRect(
            x: x,
            y: screenHeight - y - height,
            width: width,
            height: height
        )

        targetFrame = frame

        if !wasVisible {
            currentFrame = frame
            wasVisible = true
        } else {
            currentFrame = NSRect(
                x: currentFrame.minX + (targetFrame.minX - currentFrame.minX) * lerpFactor,
                y: currentFrame.minY + (targetFrame.minY - currentFrame.minY) * lerpFactor,
                width: currentFrame.width + (targetFrame.width - currentFrame.width) * lerpFactor,
                height: currentFrame.height + (targetFrame.height - currentFrame.height) * lerpFactor
            )
        }

        onFrameUpdate?(currentFrame)
    }

    private func handleDisappeared() {
        if wasVisible {
            wasVisible = false
            onWindowDisappeared?()
        }
    }
}

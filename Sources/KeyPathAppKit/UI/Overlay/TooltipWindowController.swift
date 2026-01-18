import AppKit
import SwiftUI

/// A floating tooltip window that appears after hovering over a target.
/// Only one tooltip is visible at a time (managed via shared instance).
@MainActor
final class TooltipWindowController {
    static let shared = TooltipWindowController()

    private var window: NSWindow?
    private var showTask: Task<Void, Never>?
    private var currentTooltipId: String?

    /// Delay before showing tooltip (seconds)
    private let showDelay: TimeInterval = 0.6

    private init() {}

    /// Show tooltip after delay, positioned above the given screen rect
    /// - Parameters:
    ///   - text: The tooltip text to display
    ///   - id: Unique identifier for this tooltip (to prevent duplicates)
    ///   - anchorRect: Screen coordinates of the anchor element
    func show(text: String, id: String, anchorRect: NSRect) {
        // Cancel any pending show
        showTask?.cancel()

        // If same tooltip is already showing, do nothing
        if currentTooltipId == id, window != nil {
            return
        }

        // Dismiss any existing tooltip immediately if different
        if currentTooltipId != id {
            dismissImmediately()
        }

        currentTooltipId = id

        showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(showDelay * 1_000_000_000))
            guard !Task.isCancelled, currentTooltipId == id else { return }
            showWindow(text: text, anchorRect: anchorRect)
        }
    }

    /// Dismiss the tooltip for a specific id
    func dismiss(id: String) {
        guard currentTooltipId == id else { return }
        showTask?.cancel()
        showTask = nil
        dismissWithFade()
    }

    /// Dismiss any visible tooltip immediately
    func dismissImmediately() {
        showTask?.cancel()
        showTask = nil
        currentTooltipId = nil

        guard let window else { return }
        window.orderOut(nil)
        self.window = nil
    }

    private func dismissWithFade() {
        currentTooltipId = nil

        guard let window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.orderOut(nil)
                self?.window = nil
            }
        }
    }

    private func showWindow(text: String, anchorRect: NSRect) {
        // Create tooltip view
        let tooltipView = TooltipView(text: text)
        let hostingView = NSHostingView(rootView: tooltipView)

        // Size to fit content
        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = fittingSize

        // Create borderless, transparent window
        let tooltipWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.isOpaque = false
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.level = .floating + 1 // Above other floating windows
        tooltipWindow.hasShadow = true
        tooltipWindow.ignoresMouseEvents = true
        tooltipWindow.contentView = hostingView

        // Position above the anchor, centered horizontally
        let tooltipX = anchorRect.midX - fittingSize.width / 2
        let tooltipY = anchorRect.maxY + 6 // 6pt gap above anchor
        tooltipWindow.setFrameOrigin(NSPoint(x: tooltipX, y: tooltipY))

        // Fade in
        tooltipWindow.alphaValue = 0
        tooltipWindow.orderFront(nil)
        window = tooltipWindow

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            tooltipWindow.animator().alphaValue = 1.0
        }
    }
}

/// Simple tooltip view matching macOS style
private struct TooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}

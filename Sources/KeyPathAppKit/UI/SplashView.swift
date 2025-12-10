import AppKit
import KeyPathCore
import SwiftUI

/// Splash screen dimensions (must match image aspect ratio 2304:1856 ≈ 1.24:1)
enum SplashConstants {
    static let width: CGFloat = 500
    static let height: CGFloat = 403
    static let size = CGSize(width: width, height: height)
    static let cornerRadius: CGFloat = 12
    // Dark background matching the poster's dark edges
    static let backgroundColor = NSColor(red: 30 / 255, green: 30 / 255, blue: 34 / 255, alpha: 1.0)
}

// MARK: - Borderless Splash Window Controller

/// A dedicated borderless window controller for the splash screen.
/// No traffic lights, no titlebar, no safe area - just the image edge-to-edge.
/// Uses pure AppKit NSImageView for predictable sizing.
@MainActor
final class SplashWindowController: NSWindowController {
    private var onDismiss: (() -> Void)?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

        AppLogger.shared.log("🎬 [Splash] Creating splash window with size: \(SplashConstants.size)")

        // Create borderless window - no traffic lights, no titlebar
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SplashConstants.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        AppLogger.shared.log("🎬 [Splash] Window frame after creation: \(window.frame)")

        // Configure window for clean splash display with rounded corners
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating // Stay above other windows during splash
        window.isMovableByWindowBackground = true
        window.center()

        AppLogger.shared.log("🎬 [Splash] Window frame after center(): \(window.frame)")

        // Disable window restoration for splash
        window.isRestorable = false

        super.init(window: window)

        // Create a container view with rounded corners
        let containerView = NSView(frame: NSRect(origin: .zero, size: SplashConstants.size))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = SplashConstants.cornerRadius
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = SplashConstants.backgroundColor.cgColor

        // Use pure AppKit NSImageView - predictable sizing, no SwiftUI surprises
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: SplashConstants.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        if let url = Bundle.main.url(forResource: "keypath-poster-hor", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            AppLogger.shared.log("🎬 [Splash] Image loaded - size: \(image.size), representations: \(image.representations.count)")
            if let rep = image.representations.first {
                AppLogger.shared.log("🎬 [Splash] Image rep - pixels: \(rep.pixelsWide)x\(rep.pixelsHigh), size: \(rep.size)")
            }
            imageView.image = image
        } else {
            AppLogger.shared.log("🎬 [Splash] ⚠️ Failed to load image!")
        }

        containerView.addSubview(imageView)
        window.contentView = containerView

        AppLogger.shared.log("🎬 [Splash] Final window frame: \(window.frame), contentView frame: \(containerView.frame)")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSplash(duration: TimeInterval = 5.0) {
        guard let window else { return }

        window.makeKeyAndOrderFront(nil)

        // Auto-dismiss after duration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            await dismissWithFade()
        }
    }

    func dismissWithFade() async {
        guard let window else { return }

        // Fade out animation
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0.0
            } completionHandler: {
                continuation.resume()
            }
        }

        window.orderOut(nil)
        onDismiss?()
    }
}

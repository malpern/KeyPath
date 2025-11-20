import AppKit
import KeyPathCore
import SwiftUI

/// Floating window that displays the current layer name
class LayerIndicatorWindow: NSWindow {
  private var hideTimer: Timer?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    // Window configuration
    isOpaque = false
    backgroundColor = .clear
    level = .floating  // Appears above all other windows
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isMovable = false
    hasShadow = true

    // Position at top-right of screen
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.maxX - 220  // 20px from right edge
      let y = screenFrame.maxY - 80  // 20px from top edge
      setFrameOrigin(NSPoint(x: x, y: y))
    }

    contentView = NSHostingView(rootView: LayerIndicatorView())
  }

  func show(layerName: String) {
    // Update content
    if let hostingView = contentView as? NSHostingView<LayerIndicatorView> {
      hostingView.rootView = LayerIndicatorView(layerName: layerName)
    }

    // Cancel any existing hide timer
    hideTimer?.invalidate()

    // Show window immediately (no fade-in)
    alphaValue = 1.0
    orderFront(nil)

    // Schedule fade-out after 3 seconds
    hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
      Task { @MainActor in
        self?.hideWithFadeOut()
      }
    }
  }

  @MainActor
  private func hideWithFadeOut() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.5
      animator().alphaValue = 0.0
    } completionHandler: {
      Task { @MainActor in
        self.orderOut(nil)
      }
    }
  }
}

/// SwiftUI view for the layer indicator content
struct LayerIndicatorView: View {
  var layerName: String = "base"

  var body: some View {
    VStack(spacing: 4) {
      Text("LAYER")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.6))
        .tracking(2)

      Text(layerName.uppercased())
        .font(.system(size: 24, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
    }
    .frame(width: 200, height: 60)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(.black.opacity(0.85))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
    )
  }
}

/// Manager for the layer indicator window
@MainActor
class LayerIndicatorManager: ObservableObject {
  static let shared = LayerIndicatorManager()

  private var window: LayerIndicatorWindow?

  private init() {}

  func showLayer(_ layerName: String) {
    AppLogger.shared.log("🪟 [LayerIndicator] showLayer called with: '\(layerName)'")

    // Ignore "base" layer changes to reduce noise
    guard layerName.lowercased() != "base" else {
      AppLogger.shared.log("🪟 [LayerIndicator] Ignoring base layer")
      return
    }

    if window == nil {
      AppLogger.shared.log("🪟 [LayerIndicator] Creating new window")
      window = LayerIndicatorWindow()
    }

    AppLogger.shared.log("🪟 [LayerIndicator] Showing window with layer: '\(layerName)'")
    window?.show(layerName: layerName)
  }
}

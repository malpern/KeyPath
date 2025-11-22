import AppKit
import SwiftUI

/// Lightweight floating bubble overlay presented in a borderless NSWindow
@MainActor
enum HelpBubbleOverlay {
  private static var window: NSWindow?
  private static var globalMonitor: Any?
  private static var localMonitor: Any?
  private static var autoDismissWorkItem: DispatchWorkItem?

  /// Show a floating help bubble near a screen point. Automatically dismisses after duration seconds.
  static func show(
    message: String,
    at point: NSPoint,
    duration: TimeInterval = 12,
    onDismiss: (() -> Void)? = nil
  ) {
    dismiss()  // ensure single instance

    let hosting = NSHostingView(
      rootView: BubbleView(
        message: message,
        onClose: {
          dismiss()
          onDismiss?()
        }
      ))
    hosting.wantsLayer = true

    // Measure ideal size
    let size = hosting.fittingSize == .zero ? NSSize(width: 360, height: 64) : hosting.fittingSize

    let rect = NSRect(
      x: point.x - size.width / 2, y: point.y, width: size.width, height: size.height
    )

    let win = NSWindow(
      contentRect: rect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    win.isOpaque = false
    win.backgroundColor = .clear
    win.level = .statusBar
    // Let clicks pass through so it never blocks user interaction
    win.ignoresMouseEvents = true
    win.hasShadow = true
    win.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    win.contentView = hosting
    win.makeKeyAndOrderFront(nil)
    window = win

    // Auto dismiss with cancelable work item
    let work = DispatchWorkItem {
      dismiss()
      onDismiss?()
    }
    autoDismissWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)

    // Dismiss on any mouse click (global + local to be safe)
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]) { _ in
      dismiss()
      onDismiss?()
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]) { event in
      dismiss()
      onDismiss?()
      return event
    }
  }

  static func dismiss() {
    if let work = autoDismissWorkItem {
      work.cancel()
      autoDismissWorkItem = nil
    }
    if let gm = globalMonitor {
      NSEvent.removeMonitor(gm)
      globalMonitor = nil
    }
    if let lm = localMonitor {
      NSEvent.removeMonitor(lm)
      localMonitor = nil
    }
    window?.orderOut(nil)
    window = nil
  }

  private struct BubbleView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
      HStack(spacing: 10) {
        Text(message)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.black)
          .padding(.vertical, 10)
          .padding(.leading, 14)
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black.opacity(0.7))
            .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss help bubble")
        .padding(.trailing, 6)
      }
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.yellow.opacity(0.95))
          .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
      )
      .overlay(
        // Small pointer at the top center
        TrianglePointer()
          .fill(Color.yellow.opacity(0.95))
          .frame(width: 18, height: 9)
          .offset(y: 18 / 2),
        alignment: .top
      )
      .padding(2)
    }
  }

  private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.closeSubpath()
      return path
    }
  }
}

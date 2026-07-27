import AppKit
import SwiftUI

struct KeyboardStageNativeFirstFrameProbe: NSViewRepresentable {
    let onFirstFramePresented: @MainActor @Sendable () -> Void

    func makeNSView(context _: Context) -> KeyboardStageVisibilityProbeView {
        KeyboardStageVisibilityProbeView(onVisible: onFirstFramePresented)
    }

    func updateNSView(_ view: KeyboardStageVisibilityProbeView, context _: Context) {
        view.onVisible = onFirstFramePresented
        view.reportIfVisibleOnNextDisplayTurn()
    }

    static func dismantleNSView(
        _ view: KeyboardStageVisibilityProbeView,
        coordinator _: Void
    ) {
        view.stopObservingWindow()
    }
}

@MainActor
final class KeyboardStageVisibilityProbeView: NSView {
    var onVisible: @MainActor @Sendable () -> Void

    private weak var observedWindow: NSWindow?
    private var didReport = false
    private var visibilityTask: Task<Void, Never>?

    init(onVisible: @escaping @MainActor @Sendable () -> Void) {
        self.onVisible = onVisible
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        observedWindow = window
        guard let window else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didExposeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        reportIfVisibleOnNextDisplayTurn()
    }

    func reportIfVisibleOnNextDisplayTurn() {
        guard !didReport else { return }
        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.reportIfVisible()
        }
    }

    func stopObservingWindow() {
        visibilityTask?.cancel()
        visibilityTask = nil
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow)
        }
        observedWindow = nil
    }

    @objc private func windowVisibilityChanged() {
        reportIfVisibleOnNextDisplayTurn()
    }

    private func reportIfVisible() {
        guard !didReport,
              !isHiddenOrHasHiddenAncestor,
              bounds.width > 0,
              bounds.height > 0,
              window?.isVisible == true,
              window?.isMiniaturized == false,
              window?.screen != nil
        else {
            return
        }

        didReport = true
        onVisible()
    }
}

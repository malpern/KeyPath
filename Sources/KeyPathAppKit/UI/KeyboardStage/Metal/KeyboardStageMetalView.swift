import AppKit
import MetalKit
import SwiftUI

struct KeyboardStageDrawRecovery: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case waitForEvent
        case scheduleRetry
        case fail
    }

    static let defaultRetryLimit = 4

    let retryLimit: Int
    private(set) var isPending = false
    private(set) var retriesRemaining = 0

    init(retryLimit: Int = defaultRetryLimit) {
        self.retryLimit = max(0, retryLimit)
    }

    mutating func request() {
        isPending = true
        retriesRemaining = retryLimit
    }

    mutating func complete() {
        isPending = false
        retriesRemaining = 0
    }

    mutating func drawableUnavailable(
        isViewActive: Bool,
        retryAlreadyScheduled: Bool
    ) -> Action {
        guard isPending, isViewActive else { return .waitForEvent }
        guard !retryAlreadyScheduled else { return .waitForEvent }
        guard retriesRemaining > 0 else {
            complete()
            return .fail
        }

        retriesRemaining -= 1
        return .scheduleRetry
    }
}

struct KeyboardStageMetalView: NSViewRepresentable {
    let frame: KeyboardStagePresentedFrame
    let onFirstFramePresented: @MainActor @Sendable () -> Void
    let onFailure: @MainActor @Sendable (Error) -> Void

    static var isSupported: Bool {
        KeyboardStageMetalLibrary.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFirstFramePresented: onFirstFramePresented,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> KeyboardStageMTKView {
        let view = KeyboardStageMTKView(frame: .zero)
        view.colorPixelFormat = KeyboardStageMetalLibrary.colorPixelFormat
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.layer?.isOpaque = false

        guard let device = MTLCreateSystemDefaultDevice() else {
            context.coordinator.report(KeyboardStageMetalError.noDevice)
            return view
        }

        view.device = device
        do {
            let generation = context.coordinator.beginRenderer(with: frame)
            let coordinator = context.coordinator
            let renderer = try KeyboardStageMetalRenderer(
                device: device,
                frame: frame,
                onFirstFramePresented: { [weak coordinator] in
                    coordinator?.reportFirstFramePresented(for: generation)
                },
                onFailure: { [weak coordinator] error in
                    coordinator?.report(error)
                }
            )
            context.coordinator.renderer = renderer
            view.delegate = renderer
            view.requestDraw()
        } catch {
            context.coordinator.report(error)
        }
        return view
    }

    func updateNSView(_ view: KeyboardStageMTKView, context: Context) {
        context.coordinator.updateCallbacks(
            onFirstFramePresented: onFirstFramePresented,
            onFailure: onFailure
        )
        guard context.coordinator.shouldDraw(frame) else { return }
        context.coordinator.renderer?.update(frame: frame)
        view.requestDraw()
    }

    static func dismantleNSView(_ view: KeyboardStageMTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
        coordinator.invalidateRenderer()
        view.cancelPendingDraw()
        view.stopObservingWindow()
    }

    @MainActor
    final class Coordinator: NSObject {
        var renderer: KeyboardStageMetalRenderer?
        private var frameInvalidation = KeyboardStageFrameInvalidation()
        private var firstFrameGate = KeyboardStageFirstFrameGate()
        private var onFirstFramePresented: @MainActor @Sendable () -> Void
        private var onFailure: @MainActor @Sendable (Error) -> Void

        init(
            onFirstFramePresented: @escaping @MainActor @Sendable () -> Void,
            onFailure: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            self.onFirstFramePresented = onFirstFramePresented
            self.onFailure = onFailure
        }

        func updateCallbacks(
            onFirstFramePresented: @escaping @MainActor @Sendable () -> Void,
            onFailure: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            self.onFirstFramePresented = onFirstFramePresented
            self.onFailure = onFailure
        }

        func beginRenderer(with frame: KeyboardStagePresentedFrame) -> UInt64 {
            frameInvalidation.begin(with: frame)
            return firstFrameGate.beginGeneration()
        }

        func shouldDraw(_ frame: KeyboardStagePresentedFrame) -> Bool {
            frameInvalidation.shouldDraw(frame)
        }

        func reportFirstFramePresented(for generation: UInt64) {
            guard firstFrameGate.claim(generation) else { return }
            onFirstFramePresented()
        }

        func invalidateRenderer() {
            frameInvalidation.reset()
            firstFrameGate.invalidate()
        }

        func report(_ error: Error) {
            let handler = onFailure
            Task { @MainActor in
                handler(error)
            }
        }
    }
}

final class KeyboardStageMTKView: MTKView {
    private weak var observedWindow: NSWindow?
    private var drawRecovery = KeyboardStageDrawRecovery()
    private var retryTask: Task<Void, Never>?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        observedWindow = window
        guard let window else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didExposeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameDrawable),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        requestDraw()
    }

    func requestDraw() {
        cancelRetryTask()
        drawRecovery.request()
        drawIfActive()
    }

    func drawableUnavailable() -> Bool {
        let action = drawRecovery.drawableUnavailable(
            isViewActive: isDrawableActive,
            retryAlreadyScheduled: retryTask != nil
        )
        switch action {
        case .waitForEvent:
            return true

        case .scheduleRetry:
            retryTask = Task { @MainActor [weak self] in
                try? await Task<Never, Never>.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                retryTask = nil
                drawIfActive()
            }
            return true

        case .fail:
            return false
        }
    }

    func markDrawSubmitted() {
        cancelRetryTask()
        drawRecovery.complete()
    }

    func cancelPendingDraw() {
        cancelRetryTask()
        drawRecovery.complete()
    }

    func stopObservingWindow() {
        cancelRetryTask()
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow)
        }
        observedWindow = nil
    }

    @objc private func windowBecameDrawable() {
        requestDraw()
    }

    private func drawIfActive() {
        guard drawRecovery.isPending,
              isDrawableActive
        else {
            return
        }
        setNeedsDisplay(bounds)
    }

    /// A visible, non-key onboarding window must still accept a requested draw.
    /// Otherwise the native labels advance while the Metal surfaces freeze.
    private var isDrawableActive: Bool {
        !isHiddenOrHasHiddenAncestor
            && bounds.width > 0
            && bounds.height > 0
            && window?.isVisible == true
            && window?.isMiniaturized == false
            && window?.screen != nil
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }
}

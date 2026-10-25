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
            view.windowMappingDidChange = { [weak renderer] windowX in
                renderer?.update(windowX: windowX)
            }
            context.coordinator.startTuningHarnessIfRequested(for: view)
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
        let shouldDraw = context.coordinator.shouldDraw(frame)
        context.coordinator.renderer?.update(
            frame: frame,
            windowX: view.currentWindowXMapping()
        )
        guard shouldDraw else { return }
        view.requestDraw()
    }

    static func dismantleNSView(_ view: KeyboardStageMTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
        coordinator.stopTuningHarness()
        coordinator.invalidateRenderer()
        view.windowMappingDidChange = nil
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

        // MARK: - Developer tuning harness

        private var tuningWatcher: (any DispatchSourceFileSystemObject)?

        /// When `KEYPATH_STAGE_TUNING_FILE` names a JSON file, apply it and
        /// redraw on every save so lighting constants can be tuned live
        /// instead of through a build-deploy-replay loop. Inert in normal
        /// launches: without the environment variable nothing is installed.
        func startTuningHarnessIfRequested(for view: KeyboardStageMTKView) {
            guard let url = KeyboardStageTuning.environmentFileURL else { return }
            applyTuning(from: url, to: view)
            armTuningWatcher(url: url, view: view)
        }

        func stopTuningHarness() {
            tuningWatcher?.cancel()
            tuningWatcher = nil
        }

        private func applyTuning(from url: URL, to view: KeyboardStageMTKView) {
            guard let tuning = try? KeyboardStageTuning.load(from: url) else {
                return
            }
            renderer?.update(tuning: tuning)
            view.requestDraw()
        }

        private func armTuningWatcher(url: URL, view: KeyboardStageMTKView) {
            stopTuningHarness()
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self, weak view] in
                let events = source.data
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    applyTuning(from: url, to: view)
                    // Editors save atomically by replacing the file; the old
                    // descriptor then watches a dead inode, so re-arm.
                    if events.contains(.rename) || events.contains(.delete) {
                        armTuningWatcher(url: url, view: view)
                    }
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            tuningWatcher = source
        }
    }
}

final class KeyboardStageMTKView: MTKView {
    var windowMappingDidChange: (@MainActor @Sendable (SIMD2<Float>) -> Void)?

    private weak var observedWindow: NSWindow?
    private var drawRecovery = KeyboardStageDrawRecovery()
    private var retryTask: Task<Void, Never>?
    private var reportedWindowX = SIMD2<Float>(0, 1)

    /// The renderer is visual output only; the native semantic overlay stacked
    /// above it owns pointer interaction and accessibility. As a real `NSView`
    /// this would otherwise return itself for every point inside the keyboard
    /// and swallow clicks before those hit targets could see them, so pointer
    /// presses worked in the SwiftUI fallback and silently failed whenever
    /// Metal was active.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

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
        refreshWindowXMapping()
        requestDraw()
    }

    override func layout() {
        super.layout()
        refreshWindowXMapping()
    }

    func currentWindowXMapping() -> SIMD2<Float> {
        guard let contentView = window?.contentView,
              contentView.bounds.width > 0
        else {
            return SIMD2(0, 1)
        }

        let frame = convert(bounds, to: contentView)
        return SIMD2(
            Float(frame.minX / contentView.bounds.width),
            Float(frame.width / contentView.bounds.width)
        )
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

    /// The entrance clock must not start behind another app. A fresh request is
    /// retained while inactive and retried by the key/occlusion observers when
    /// the onboarding window is actually in front of the user.
    private var isDrawableActive: Bool {
        !isHiddenOrHasHiddenAncestor
            && bounds.width > 0
            && bounds.height > 0
            && window?.isVisible == true
            && window?.isMiniaturized == false
            && window?.screen != nil
            && window?.occlusionState.contains(.visible) == true
            && window?.isKeyWindow == true
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func refreshWindowXMapping() {
        let mapping = currentWindowXMapping()
        guard mapping != reportedWindowX else { return }
        reportedWindowX = mapping
        windowMappingDidChange?(mapping)
        requestDraw()
    }
}

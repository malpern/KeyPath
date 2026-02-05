import AppKit
import Combine
import KeyPathCore
import SwiftUI

extension LiveKeyboardOverlayController {
    // MARK: - Inspector Panel

    func openInspector(animated: Bool) {
        guard let window else { return }
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let baseFrame = window.frame
        collapsedFrameBeforeInspector = baseFrame

        let maxVisibleX = window.screen?.visibleFrame.maxX
        let expandedFrame = InspectorPanelLayout.expandedFrame(
            baseFrame: baseFrame,
            inspectorWidth: inspectorTotalWidth,
            maxVisibleX: maxVisibleX
        )

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📤 [OverlayInspector] open start frame=\(baseFrame.debugDescription) " +
                    "expanded=\(expandedFrame.debugDescription) totalW=\(inspectorTotalWidth.rounded())"
            )
        }

        uiState.isInspectorClosing = false
        uiState.isInspectorAnimating = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 1)
            setWindowFrame(expandedFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.isInspectorOpen = true
                uiState.inspectorReveal = 1
                lastWindowFrame = expandedFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📤 [OverlayInspector] open end frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            uiState.inspectorReveal = 1
            setWindowFrame(expandedFrame, animated: false)
            uiState.isInspectorOpen = true
            uiState.isInspectorAnimating = false
            lastWindowFrame = expandedFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📤 [OverlayInspector] open instant frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    func closeInspector(animated: Bool) {
        guard let window else { return }
        guard uiState.isInspectorOpen || uiState.inspectorReveal > 0 || uiState.isInspectorAnimating else {
            uiState.isInspectorClosing = false
            return
        }
        let targetFrame = collapsedFrameBeforeInspector ?? InspectorPanelLayout.collapsedFrame(
            expandedFrame: window.frame,
            inspectorWidth: inspectorTotalWidth
        )
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📥 [OverlayInspector] close start frame=\(window.frame.debugDescription) " +
                    "target=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
            )
        }

        uiState.isInspectorAnimating = shouldAnimate
        uiState.isInspectorClosing = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 0)
            setWindowFrame(targetFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.inspectorReveal = 0
                uiState.isInspectorOpen = false
                uiState.isInspectorClosing = false
                collapsedFrameBeforeInspector = nil
                lastWindowFrame = targetFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📥 [OverlayInspector] close end frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            setWindowFrame(targetFrame, animated: false)
            uiState.inspectorReveal = 0
            uiState.isInspectorOpen = false
            uiState.isInspectorAnimating = false
            uiState.isInspectorClosing = false
            collapsedFrameBeforeInspector = nil
            lastWindowFrame = targetFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📥 [OverlayInspector] close instant frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    /// Animate inspector reveal from current value to target (0 or 1)
    func animateInspectorReveal(to targetReveal: CGFloat) {
        let startTime = CACurrentMediaTime()
        let startReveal = uiState.inspectorReveal
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / inspectorAnimationDuration)
                uiState.inspectorReveal = OverlayInspectorMath.revealValue(
                    start: startReveal,
                    target: targetReveal,
                    elapsed: elapsed,
                    duration: inspectorAnimationDuration
                )

                if progress >= 1.0 {
                    inspectorAnimationTimer?.invalidate()
                    inspectorAnimationTimer = nil
                }
            }
        }
    }

    /// Clean up animation state after completion
    func finalizeInspectorAnimation() {
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = nil
        uiState.isInspectorAnimating = false
    }

    func handleWindowFrameChange() {
        guard let window else { return }
        if uiState.isInspectorOpen, !uiState.isInspectorClosing {
            updateCollapsedFrame(forExpandedFrame: window.frame)
        }
        if uiState.isInspectorAnimating {
            updateInspectorRevealFromWindow()
            if inspectorDebugEnabled {
                let now = CFAbsoluteTimeGetCurrent()
                if now - inspectorDebugLastLog > 0.2 {
                    inspectorDebugLastLog = now
                    let revealStr = String(format: "%.3f", uiState.inspectorReveal)
                    AppLogger.shared.log(
                        "🪟 [OverlayInspector] frame=\(window.frame.debugDescription) " +
                            "reveal=\(revealStr) " +
                            "animating=\(uiState.isInspectorAnimating) closing=\(uiState.isInspectorClosing)"
                    )
                }
            }
            return
        }
        saveWindowFrame()
        lastWindowFrame = window.frame
    }

    func updateInspectorRevealFromWindow() {
        guard let window else { return }
        let collapsedWidth = collapsedFrameBeforeInspector?.width ?? max(0, window.frame.width - inspectorTotalWidth)
        uiState.inspectorReveal = OverlayInspectorMath.clampedReveal(
            expandedWidth: window.frame.width,
            collapsedWidth: collapsedWidth,
            inspectorWidth: inspectorTotalWidth
        )
    }

    func updateCollapsedFrame(forExpandedFrame expandedFrame: NSRect) {
        var baseFrame = collapsedFrameBeforeInspector ?? expandedFrame
        if let lastFrame = lastWindowFrame {
            let deltaX = expandedFrame.origin.x - lastFrame.origin.x
            let deltaY = expandedFrame.origin.y - lastFrame.origin.y
            baseFrame.origin.x += deltaX
            baseFrame.origin.y += deltaY
        } else {
            baseFrame.origin = expandedFrame.origin
        }
        baseFrame.size.width = max(0, expandedFrame.width - inspectorTotalWidth)
        baseFrame.size.height = expandedFrame.height
        collapsedFrameBeforeInspector = baseFrame
    }

    func setWindowFrame(_ frame: NSRect, animated: Bool, duration: TimeInterval? = nil) {
        guard let window else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration ?? inspectorAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    func observeDesiredContentHeight() {
        uiState.$desiredContentHeight
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self, !self.isUserResizing else { return }
                applyDesiredContentHeight(height)
            }
            .store(in: &cancellables)
    }

    func observeDesiredContentWidth() {
        uiState.$desiredContentWidth
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self, !self.isUserResizing else { return }
                applyDesiredContentWidth(width)
            }
            .store(in: &cancellables)
    }

    /// Show the hide hint bubble after health indicator dismisses
    /// Waits for health indicator to disappear, then 0.5s delay, then shows bubble
    func showHintBubbleAfterHealthIndicator() {
        // Cancel any existing observer
        hintBubbleObserver?.cancel()

        // If health indicator is already dismissed, show after short delay
        if uiState.healthIndicatorState == .dismissed || uiState.healthIndicatorState == .healthy {
            showHintBubbleWithDelay(seconds: 0.5)
            return
        }

        // Otherwise, observe and wait for dismissal
        hintBubbleObserver = uiState.$healthIndicatorState
            .filter { $0 == .dismissed || $0 == .healthy }
            .first()
            .sink { [weak self] _ in
                self?.showHintBubbleWithDelay(seconds: 0.5)
            }
    }

    func showHintBubbleWithDelay(seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let window = self.window, window.isVisible else { return }

            // Create controller if needed
            if hintWindowController == nil {
                hintWindowController = HideHintWindowController()
            }

            hintWindowController?.show(above: window)
        }
    }

    /// Dismiss the hide hint bubble if visible
    func dismissHintBubble() {
        hintBubbleObserver?.cancel()
        hintBubbleObserver = nil
        hintWindowController?.dismiss()
    }

    func observeKeyboardAspectRatio() {
        uiState.$keyboardAspectRatio
            .removeDuplicates()
            .sink { [weak self] newAspectRatio in
                guard let self, !self.isUserResizing else { return }
                resizeWindowForNewAspectRatio(newAspectRatio)
            }
            .store(in: &cancellables)
    }

    func resizeWindowForNewAspectRatio(_ newAspectRatio: CGFloat) {
        guard let window else { return }
        guard !isAdjustingHeight, !isAdjustingWidth else { return }

        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let currentFrame = window.frame

        // Calculate new keyboard width based on new aspect ratio
        // Calculate horizontal chrome (padding + inspector if open)
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: uiState.isInspectorOpen,
            inspectorWidth: inspectorPanelWidth
        )

        let newWindowWidth = OverlayWindowResizer.widthForAspect(
            currentHeight: currentFrame.height,
            aspect: newAspectRatio,
            verticalChrome: verticalChrome,
            horizontalChrome: horizontalChrome
        )

        // Only resize if there's a meaningful difference
        guard abs(currentFrame.width - newWindowWidth) > 1.0 else { return }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = newWindowWidth

        // Keep right edge anchored (window moves left as it shrinks, right as it grows)
        newFrame.origin.x = currentFrame.maxX - newWindowWidth

        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)

        isAdjustingWidth = false
    }

    func applyDesiredContentHeight(_ height: CGFloat) {
        guard let window else { return }
        guard height > 0 else { return }
        guard !isAdjustingHeight else { return }

        let currentFrame = window.frame
        if abs(currentFrame.height - height) < 0.5 {
            return
        }

        isAdjustingHeight = true
        var newFrame = currentFrame
        newFrame.size.height = height
        newFrame.origin.y = currentFrame.maxY - height
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: false)
        isAdjustingHeight = false
    }

    func applyDesiredContentWidth(_ width: CGFloat) {
        guard let window else { return }
        guard width > 0 else { return }
        guard !isAdjustingWidth else { return }
        guard uiState.isInspectorOpen else { return } // Only resize when inspector is open

        let currentFrame = window.frame
        if abs(currentFrame.width - width) < 0.5 {
            return
        }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = width
        // Keep right edge anchored (inspector stays in place)
        newFrame.origin.x = currentFrame.maxX - width
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)
        // Update collapsed frame reference to maintain correct keyboard width
        updateCollapsedFrame(forExpandedFrame: constrained)
        isAdjustingWidth = false
    }

    func resolveResizeAnchor(widthDelta: CGFloat, heightDelta: CGFloat) -> OverlayResizeAnchor {
        let threshold: CGFloat = 6
        let currentMouse = NSEvent.mouseLocation
        let resolved = OverlayWindowResizer.resolveAnchor(
            existing: resizeAnchor,
            startFrame: resizeStartFrame,
            currentFrame: window?.frame,
            startMouse: resizeStartMouse,
            currentMouse: currentMouse,
            widthDelta: widthDelta,
            heightDelta: heightDelta,
            threshold: threshold
        )
        resizeAnchor = resolved
        return resolved
    }
}

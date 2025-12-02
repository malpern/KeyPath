import AppKit
import Carbon
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var layout: PhysicalLayout = .macBookUS
    /// Fade level for outline state (0 = fully visible, 1 = outline-only faded)
    @Published var fadeAmount: CGFloat = 0
    /// Deep fade level for full keyboard opacity (0 = normal, 1 = 5% visible)
    @Published var deepFadeAmount: CGFloat = 0

    // MARK: - Layer State

    /// Current Kanata layer name (e.g., "base", "nav", "symbols")
    @Published var currentLayerName: String = "base"
    /// Whether the layer key mapping is being built (for loading indicator)
    @Published var isLoadingLayerMap: Bool = false
    /// Key mapping for the current layer: keyCode -> LayerKeyInfo
    @Published var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Effective key codes that should appear pressed (includes remapped outputs)
    /// When H is pressed and maps to Left Arrow, both H and Left Arrow should highlight
    var effectivePressedKeyCodes: Set<UInt16> {
        var result = pressedKeyCodes
        // Add output key codes for all pressed keys
        for keyCode in pressedKeyCodes {
            if let info = layerKeyMap[keyCode],
               let outputKeyCode = info.outputKeyCode,
               outputKeyCode != keyCode {
                result.insert(outputKeyCode)
            }
        }
        return result
    }

    /// Service for building layer key mappings
    private let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    private var layerMapTask: Task<Void, Never>?

    // Event tap for listening to keyDown and keyUp events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isCapturing = false
    private var idleMonitorTask: Task<Void, Never>?
    private var lastInteraction: Date = .init()

    private let idleTimeout: TimeInterval = 10
    private let deepFadeTimeout: TimeInterval = 48
    private let deepFadeRamp: TimeInterval = 2
    private let idlePollInterval: TimeInterval = 0.25

    func startCapturing() {
        guard !isCapturing else {
            AppLogger.shared.debug("⌨️ [KeyboardViz] Already capturing, ignoring start request")
            return
        }

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Test environment - skipping event tap")
            return
        }

        // Check permissions silently
        guard AXIsProcessTrusted() else {
            AppLogger.shared.warn("⚠️ [KeyboardViz] Accessibility permission required")
            return
        }

        setupEventTap()
        startIdleMonitor()
        rebuildLayerMapping() // Build initial layer mapping
    }

    func stopCapturing() {
        guard isCapturing else { return }

        isCapturing = false
        pressedKeyCodes.removeAll()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        idleMonitorTask?.cancel()
        idleMonitorTask = nil

        AppLogger.shared.debug("⌨️ [KeyboardViz] Stopped capturing")
    }

    func isPressed(_ key: PhysicalKey) -> Bool {
        pressedKeyCodes.contains(key.keyCode)
    }

    // MARK: - Private Event Handling

    private func setupEventTap() {
        // Listen to keyDown, keyUp, and flagsChanged (for modifier keys like Caps Lock)
        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // Listen-only mode - don't interfere with other apps
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let viewModel = Unmanaged<KeyboardVisualizationViewModel>.fromOpaque(refcon)
                    .takeUnretainedValue()

                viewModel.handleKeyEvent(event: event, type: type)

                // Always pass event through (listen-only mode)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            AppLogger.shared.error("❌ [KeyboardViz] Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isCapturing = true

        AppLogger.shared.info("✅ [KeyboardViz] Event tap created (listen-only mode)")
    }

    private func handleKeyEvent(event: CGEvent, type: CGEventType) {
        // Ignore autorepeat frames
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return
        }

        noteInteraction()

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        Task { @MainActor in
            switch type {
            case .keyDown:
                pressedKeyCodes.insert(keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyDown: \(keyCode)")

            case .keyUp:
                pressedKeyCodes.remove(keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyUp: \(keyCode)")

            case .flagsChanged:
                // Handle modifier key presses (Caps Lock, Shift, Cmd, etc.)
                handleFlagsChanged(event: event, keyCode: keyCode)

            default:
                break
            }
        }
    }

    /// Handle modifier key state changes from flagsChanged events
    private func handleFlagsChanged(event: CGEvent, keyCode: UInt16) {
        let flags = event.flags

        // Update only the modifier key that triggered this flagsChanged event so previously-held
        // modifiers stay pressed (e.g., holding ⌘ while pressing ⌥).
        switch keyCode {
        case 57: // Caps Lock
            updateModifierState(keyCode: 57, isPressed: flags.contains(.maskAlphaShift))
        case 56: // Left Shift
            updateModifierState(keyCode: 56, isPressed: flags.contains(.maskShift))
        case 60: // Right Shift
            updateModifierState(keyCode: 60, isPressed: flags.contains(.maskShift))
        case 59: // Left Control
            updateModifierState(keyCode: 59, isPressed: flags.contains(.maskControl))
        case 55: // Left Command
            updateModifierState(keyCode: 55, isPressed: flags.contains(.maskCommand))
        case 54: // Right Command
            updateModifierState(keyCode: 54, isPressed: flags.contains(.maskCommand))
        case 58: // Left Option
            updateModifierState(keyCode: 58, isPressed: flags.contains(.maskAlternate))
        case 61: // Right Option
            updateModifierState(keyCode: 61, isPressed: flags.contains(.maskAlternate))
        case 63: // Fn key
            updateModifierState(keyCode: 63, isPressed: flags.contains(.maskSecondaryFn))
        default:
            break
        }

        // Final reconciliation: if a modifier flag is absent, ensure both sides of that modifier
        // are cleared so simultaneous releases don't leave a side stuck as "pressed".
        reconcileModifierStates(flags: flags)

        AppLogger.shared.debug("⌨️ [KeyboardViz] FlagsChanged: keyCode=\(keyCode), flags=\(flags.rawValue)")
    }

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        lastInteraction = Date()

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(idlePollInterval))

                // Don't fade while holding a momentary layer key (non-base layer active)
                let isOnMomentaryLayer = currentLayerName.lowercased() != "base"
                if isOnMomentaryLayer {
                    // Keep overlay fully visible while on a non-base layer
                    if fadeAmount != 0 { fadeAmount = 0 }
                    if deepFadeAmount != 0 { deepFadeAmount = 0 }
                    continue
                }

                let elapsed = Date().timeIntervalSince(lastInteraction)

                // Stage 1: outline fade begins after idleTimeout, completes over 5s
                // Use pow(x, 0.7) easing so changes are faster initially and gentler at the end,
                // avoiding the perceptual "cliff" when linear formulas hit their endpoints together.
                let linearProgress = max(0, min(1, (elapsed - idleTimeout) / 5))
                let fadeProgress = pow(linearProgress, 0.7)
                if fadeProgress != fadeAmount {
                    fadeAmount = fadeProgress
                }

                // Stage 2: deep fade to 5% after deepFadeTimeout over deepFadeRamp seconds
                let deepProgress = max(0, min(1, (elapsed - deepFadeTimeout) / deepFadeRamp))
                if deepProgress != deepFadeAmount {
                    deepFadeAmount = deepProgress
                }
            }
        }
    }

    /// Reset idle timer and un-fade if necessary.
    func noteInteraction() {
        lastInteraction = Date()
        if fadeAmount != 0 { fadeAmount = 0 }
        if deepFadeAmount != 0 { deepFadeAmount = 0 }
    }

    // MARK: - Layer Mapping

    /// Update the current layer and rebuild key mapping
    func updateLayer(_ layerName: String) {
        currentLayerName = layerName
        // Reset idle timer on any layer change (including returning to base)
        noteInteraction()
        rebuildLayerMapping()
    }

    /// Rebuild the key mapping for the current layer
    func rebuildLayerMapping() {
        // Cancel any in-flight mapping task
        layerMapTask?.cancel()

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Skipping layer mapping in test environment")
            return
        }

        isLoadingLayerMap = true
        AppLogger.shared.info("🗺️ [KeyboardViz] Starting layer mapping build for '\(currentLayerName)'...")

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                AppLogger.shared.debug("🗺️ [KeyboardViz] Using config: \(configPath)")

                // Build mapping for current layer
                let mapping = try await layerKeyMapper.getMapping(
                    for: currentLayerName,
                    configPath: configPath
                )

                // Update on main actor
                await MainActor.run {
                    self.layerKeyMap = mapping
                    self.isLoadingLayerMap = false
                }

                AppLogger.shared.info("🗺️ [KeyboardViz] Built layer mapping for '\(currentLayerName)': \(mapping.count) keys")

                // Log a few sample mappings for debugging
                for (keyCode, info) in mapping.prefix(5) {
                    AppLogger.shared.debug("  keyCode \(keyCode) -> '\(info.displayLabel)'")
                }
            } catch {
                AppLogger.shared.error("❌ [KeyboardViz] Failed to build layer mapping: \(error)")
                await MainActor.run {
                    self.isLoadingLayerMap = false
                }
            }
        }
    }

    /// Invalidate cached mappings (call when config changes)
    func invalidateLayerMappings() {
        Task {
            await layerKeyMapper.invalidateCache()
            rebuildLayerMapping()
        }
    }

    /// Clear modifier keycodes when the corresponding flag is fully released.
    private func reconcileModifierStates(flags: CGEventFlags) {
        if !flags.contains(.maskCommand) {
            pressedKeyCodes.remove(55) // Left Command
            pressedKeyCodes.remove(54) // Right Command
        }
        if !flags.contains(.maskAlternate) {
            pressedKeyCodes.remove(58) // Left Option
            pressedKeyCodes.remove(61) // Right Option
        }
        if !flags.contains(.maskShift) {
            pressedKeyCodes.remove(56) // Left Shift
            pressedKeyCodes.remove(60) // Right Shift
        }
        if !flags.contains(.maskControl) {
            pressedKeyCodes.remove(59) // Left Control
            pressedKeyCodes.remove(62) // Right Control (defensive)
        }
        if !flags.contains(.maskAlphaShift) {
            pressedKeyCodes.remove(57) // Caps Lock
        }
        if !flags.contains(.maskSecondaryFn) {
            pressedKeyCodes.remove(63) // Fn key
        }
    }

    #if DEBUG
        /// Test helper to simulate a flagsChanged event without installing an event tap.
        func simulateFlagsChanged(flags: CGEventFlags, keyCode: UInt16) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                return
            }
            event.flags = flags
            handleKeyEvent(event: event, type: .flagsChanged)
        }
    #endif

    private func updateModifierState(keyCode: UInt16, isPressed: Bool) {
        if isPressed {
            pressedKeyCodes.insert(keyCode)
        } else {
            pressedKeyCodes.remove(keyCode)
        }
    }
}

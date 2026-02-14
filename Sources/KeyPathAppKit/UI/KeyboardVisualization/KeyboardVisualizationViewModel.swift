import AppKit
import Carbon
import Foundation
import KeyPathCore
import Observation
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
@Observable
class KeyboardVisualizationViewModel {
    // MARK: - Key State

    /// Key codes currently pressed (from Kanata TCP KeyInput events)
    var pressedKeyCodes: Set<UInt16> = []
    var layout: PhysicalLayout = .macBookUS
    /// Fade level for outline state (0 = fully visible, 1 = outline-only faded)
    var fadeAmount: CGFloat = 0
    /// Deep fade level for full keyboard opacity (0 = normal, 1 = 5% visible)
    var deepFadeAmount: CGFloat = 0
    /// Per-key fade amounts for release animation (keyCode -> fade amount 0-1)
    var keyFadeAmounts: [UInt16: CGFloat] = [:]
    /// Active fade-out timers for released keys
    @ObservationIgnored var fadeOutTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: - Layer State

    /// Current Kanata layer name (e.g., "base", "nav", "symbols")
    var currentLayerName: String = "base"
    /// Whether the layer key mapping is being built (for loading indicator)
    var isLoadingLayerMap: Bool = false
    /// Key code of the currently selected key in the mapper drawer (nil when no selection)
    /// Used to show a visual highlight on the key being edited
    var selectedKeyCode: UInt16?
    /// Key code being hovered in rules/launcher tabs (for secondary highlight)
    var hoveredRuleKeyCode: UInt16?
    /// Key mapping for the current layer: keyCode -> LayerKeyInfo
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Hold labels for tap-hold keys that have transitioned to hold state
    /// Maps keyCode -> hold display label (e.g., "*" for Hyper)
    var holdLabels: [UInt16: String] = [:]
    /// Idle labels for tap-hold inputs (show tap output when not pressed)
    var tapHoldIdleLabels: [UInt16: String] = [:]
    /// Keys currently in a hold-active state (set when HoldActivated fires).
    /// Used to keep the key visually pressed even if tap-hold implementations
    /// emit spurious release/press events while held.
    @ObservationIgnored var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg (keyCode -> icon name)
    /// Example: "arrow-left", "safari", "home"
    var customIcons: [UInt16: String] = [:]
    /// Most recently pressed key (for icon association)
    @ObservationIgnored var lastPressedKeyCode: UInt16?
    /// Icon clear tasks (keyCode -> task that clears the icon)
    @ObservationIgnored var iconClearTasks: [UInt16: Task<Void, Never>] = [:]
    /// Keys emphasized via push-msg emphasis command
    /// Example: (push-msg "emphasis:h,j,k,l") sets HJKL as emphasized
    var customEmphasisKeyCodes: Set<UInt16> = []

    // MARK: - Launcher Mode State

    /// Launcher mappings for overlay display (key -> LauncherMapping)
    /// Loaded when entering launcher layer
    var launcherMappings: [String: LauncherMapping] = [:]

    // MARK: - Optional Feature Collections

    /// Whether the Typing Sounds collection is enabled
    var isTypingSoundsEnabled: Bool = false

    // MARK: - TCP Connection State

    /// Whether Kanata TCP server is responding (based on receiving events)
    /// When false, overlay shows "not connected" indicator
    var isKanataConnected: Bool = false

    /// Last time we received any TCP event (for connection timeout detection)
    @ObservationIgnored var lastTcpEventTime: Date?

    /// How long without events before we consider disconnected (seconds)
    @ObservationIgnored let tcpConnectionTimeout: TimeInterval = 3.0

    // MARK: - One-Shot Modifier State

    /// Active one-shot modifiers (modifier key names like "lsft", "lctl")
    /// Cleared on next key press after activation
    var activeOneShotModifiers: Set<String> = []

    /// Tracks keys currently undergoing async hold-label resolution to avoid duplicate simulator runs
    @ObservationIgnored var resolvingHoldLabels: Set<UInt16> = []
    /// Short-lived cache of resolved hold labels to avoid repeated simulator runs (keyCode -> (label, timestamp))
    @ObservationIgnored var holdLabelCache: [UInt16: (label: String, timestamp: Date)] = [:]
    /// Cache time-to-live in seconds
    @ObservationIgnored let holdLabelCacheTTL: TimeInterval = 5
    /// Pending delayed clears for hold-active keys to tolerate tap-hold-press jitter
    @ObservationIgnored var holdClearWorkItems: [UInt16: DispatchWorkItem] = [:]

    // MARK: - Tap-Hold Output Suppression

    /// Dynamically tracks tap-hold source keys to their tap output keys.
    /// Populated when TapActivated events are received from Kanata.
    /// Example: capslock (57) -> esc (53) when TapActivated says key=caps, action=esc
    @ObservationIgnored var dynamicTapHoldOutputMap: [UInt16: Set<UInt16>] = [:]

    /// Output keyCodes that should be temporarily suppressed due to recent tap activation.
    /// Populated when TapActivated fires (since the source key may already be released).
    /// Auto-cleared after a brief delay.
    @ObservationIgnored var recentTapOutputs: Set<UInt16> = []

    /// Pending tasks to clear tap outputs from temporary suppression
    @ObservationIgnored var tapOutputClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Source keys that are currently pressed (for output suppression).
    /// While a source key is in this set, its mapped output keys won't be added to pressedKeyCodes.
    @ObservationIgnored var activeTapHoldSources: Set<UInt16> = []

    // MARK: - Remap Output Suppression

    /// Maps input keyCode -> output keyCode for simple remaps.
    /// Built from layerKeyMap when mappings change.
    /// Example: A->B mapping would have [0: 11] (keyCode 0=A maps to keyCode 11=B)
    @ObservationIgnored var remapOutputMap: [UInt16: UInt16] = [:]

    /// Recently released remap source keys kept briefly to suppress delayed outputs.
    @ObservationIgnored var recentRemapSourceKeyCodes: Set<UInt16> = []
    /// Pending tasks to clear remap sources from temporary suppression.
    @ObservationIgnored var remapSourceClearTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: - Observers

    /// Key input notification observer
    @ObservationIgnored var keyInputObserver: Any?
    /// TCP heartbeat notification observer (layer polling)
    @ObservationIgnored var tcpHeartbeatObserver: Any?
    /// Hold activated notification observer
    @ObservationIgnored var holdActivatedObserver: Any?
    /// Tap activated notification observer
    @ObservationIgnored var tapActivatedObserver: Any?
    /// Push message notification observer (for icon/emphasis messages)
    @ObservationIgnored var messagePushObserver: Any?
    /// Rule collections changed notification observer (for feature toggle updates)
    @ObservationIgnored var ruleCollectionsObserver: Any?
    /// One-shot activated notification observer
    @ObservationIgnored var oneShotObserver: Any?
    /// App context observation task (for app-specific key overrides)
    @ObservationIgnored var appContextObservationTask: Task<Void, Never>?
    /// Current app's bundle identifier for overlay updates
    @ObservationIgnored var currentAppBundleId: String?

    // MARK: - Layer Mapping

    /// Service for building layer key mappings
    @ObservationIgnored let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    @ObservationIgnored var layerMapTask: Task<Void, Never>?

    // MARK: - Idle Monitoring

    @ObservationIgnored var isCapturing = false
    @ObservationIgnored var idleMonitorTask: Task<Void, Never>?
    @ObservationIgnored var lastInteraction: Date = .init()

    @ObservationIgnored let idleTimeout: TimeInterval = 10
    @ObservationIgnored let deepFadeTimeout: TimeInterval = 48
    @ObservationIgnored let deepFadeRamp: TimeInterval = 2
    @ObservationIgnored let idlePollInterval: TimeInterval = 0.25
}

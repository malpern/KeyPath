import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    // MARK: - Key State

    /// Key codes currently pressed (from Kanata TCP KeyInput events)
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var layout: PhysicalLayout = .macBookUS
    /// Fade level for outline state (0 = fully visible, 1 = outline-only faded)
    @Published var fadeAmount: CGFloat = 0
    /// Deep fade level for full keyboard opacity (0 = normal, 1 = 5% visible)
    @Published var deepFadeAmount: CGFloat = 0
    /// Per-key fade amounts for release animation (keyCode -> fade amount 0-1)
    @Published var keyFadeAmounts: [UInt16: CGFloat] = [:]
    /// Active fade-out timers for released keys
    var fadeOutTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: - Layer State

    /// Current Kanata layer name (e.g., "base", "nav", "symbols")
    @Published var currentLayerName: String = "base"
    /// Whether the layer key mapping is being built (for loading indicator)
    @Published var isLoadingLayerMap: Bool = false
    /// Key code of the currently selected key in the mapper drawer (nil when no selection)
    /// Used to show a visual highlight on the key being edited
    @Published var selectedKeyCode: UInt16?
    /// Key code being hovered in rules/launcher tabs (for secondary highlight)
    @Published var hoveredRuleKeyCode: UInt16?
    /// Key mapping for the current layer: keyCode -> LayerKeyInfo
    @Published var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Hold labels for tap-hold keys that have transitioned to hold state
    /// Maps keyCode -> hold display label (e.g., "*" for Hyper)
    @Published var holdLabels: [UInt16: String] = [:]
    /// Idle labels for tap-hold inputs (show tap output when not pressed)
    @Published var tapHoldIdleLabels: [UInt16: String] = [:]
    /// Keys currently in a hold-active state (set when HoldActivated fires).
    /// Used to keep the key visually pressed even if tap-hold implementations
    /// emit spurious release/press events while held.
    var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg (keyCode -> icon name)
    /// Example: "arrow-left", "safari", "home"
    @Published var customIcons: [UInt16: String] = [:]
    /// Most recently pressed key (for icon association)
    var lastPressedKeyCode: UInt16?
    /// Icon clear tasks (keyCode -> task that clears the icon)
    var iconClearTasks: [UInt16: Task<Void, Never>] = [:]
    /// Keys emphasized via push-msg emphasis command
    /// Example: (push-msg "emphasis:h,j,k,l") sets HJKL as emphasized
    @Published var customEmphasisKeyCodes: Set<UInt16> = []

    // MARK: - Launcher Mode State

    /// Launcher mappings for overlay display (key -> LauncherMapping)
    /// Loaded when entering launcher layer
    @Published var launcherMappings: [String: LauncherMapping] = [:]

    // MARK: - Optional Feature Collections

    /// Whether the Typing Sounds collection is enabled
    @Published var isTypingSoundsEnabled: Bool = false

    // MARK: - TCP Connection State

    /// Whether Kanata TCP server is responding (based on receiving events)
    /// When false, overlay shows "not connected" indicator
    @Published var isKanataConnected: Bool = false

    /// Last time we received any TCP event (for connection timeout detection)
    var lastTcpEventTime: Date?

    /// How long without events before we consider disconnected (seconds)
    let tcpConnectionTimeout: TimeInterval = 3.0

    // MARK: - One-Shot Modifier State

    /// Active one-shot modifiers (modifier key names like "lsft", "lctl")
    /// Cleared on next key press after activation
    @Published var activeOneShotModifiers: Set<String> = []

    /// Tracks keys currently undergoing async hold-label resolution to avoid duplicate simulator runs
    var resolvingHoldLabels: Set<UInt16> = []
    /// Short-lived cache of resolved hold labels to avoid repeated simulator runs (keyCode -> (label, timestamp))
    var holdLabelCache: [UInt16: (label: String, timestamp: Date)] = [:]
    /// Cache time-to-live in seconds
    let holdLabelCacheTTL: TimeInterval = 5
    /// Pending delayed clears for hold-active keys to tolerate tap-hold-press jitter
    var holdClearWorkItems: [UInt16: DispatchWorkItem] = [:]

    // MARK: - Tap-Hold Output Suppression

    /// Dynamically tracks tap-hold source keys to their tap output keys.
    /// Populated when TapActivated events are received from Kanata.
    /// Example: capslock (57) -> esc (53) when TapActivated says key=caps, action=esc
    var dynamicTapHoldOutputMap: [UInt16: Set<UInt16>] = [:]

    /// Output keyCodes that should be temporarily suppressed due to recent tap activation.
    /// Populated when TapActivated fires (since the source key may already be released).
    /// Auto-cleared after a brief delay.
    var recentTapOutputs: Set<UInt16> = []

    /// Pending tasks to clear tap outputs from temporary suppression
    var tapOutputClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Source keys that are currently pressed (for output suppression).
    /// While a source key is in this set, its mapped output keys won't be added to pressedKeyCodes.
    var activeTapHoldSources: Set<UInt16> = []

    // MARK: - Remap Output Suppression

    /// Maps input keyCode -> output keyCode for simple remaps.
    /// Built from layerKeyMap when mappings change.
    /// Example: A->B mapping would have [0: 11] (keyCode 0=A maps to keyCode 11=B)
    var remapOutputMap: [UInt16: UInt16] = [:]

    /// Recently released remap source keys kept briefly to suppress delayed outputs.
    var recentRemapSourceKeyCodes: Set<UInt16> = []
    /// Pending tasks to clear remap sources from temporary suppression.
    var remapSourceClearTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: - Observers

    /// Key input notification observer
    var keyInputObserver: Any?
    /// TCP heartbeat notification observer (layer polling)
    var tcpHeartbeatObserver: Any?
    /// Hold activated notification observer
    var holdActivatedObserver: Any?
    /// Tap activated notification observer
    var tapActivatedObserver: Any?
    /// Push message notification observer (for icon/emphasis messages)
    var messagePushObserver: Any?
    /// Rule collections changed notification observer (for feature toggle updates)
    var ruleCollectionsObserver: Any?
    /// One-shot activated notification observer
    var oneShotObserver: Any?
    /// App context change subscription (for app-specific key overrides)
    var appContextCancellable: AnyCancellable?
    /// Current app's bundle identifier for overlay updates
    var currentAppBundleId: String?

    // MARK: - Layer Mapping

    /// Service for building layer key mappings
    let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    var layerMapTask: Task<Void, Never>?

    // MARK: - Idle Monitoring

    var isCapturing = false
    var idleMonitorTask: Task<Void, Never>?
    var lastInteraction: Date = .init()

    let idleTimeout: TimeInterval = 10
    let deepFadeTimeout: TimeInterval = 48
    let deepFadeRamp: TimeInterval = 2
    let idlePollInterval: TimeInterval = 0.25
}

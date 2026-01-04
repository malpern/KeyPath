import AppKit
import Foundation
import KeyPathCore

/// Manages advanced key behavior configuration: hold actions, tap-dance steps, and timing.
///
/// Extracted from MapperViewModel to improve separation of concerns.
/// This component handles the state and logic for:
/// - Hold behavior (basic, trigger early, quick tap, custom keys)
/// - Tap-dance steps (double tap, triple tap, etc.)
/// - Timing configuration (tap timeout, hold timeout)
/// - Conflict detection between hold and tap-dance
@MainActor
public final class AdvancedBehaviorManager: ObservableObject {
    // MARK: - Hold Behavior

    /// Type of hold behavior for tap-hold keys
    public enum HoldBehaviorType: String, CaseIterable, Sendable {
        case basic = "Basic"
        case triggerEarly = "Trigger early"
        case quickTap = "Quick tap"
        case customKeys = "Custom keys"

        public var description: String {
            switch self {
            case .basic:
                "Hold activates after timeout"
            case .triggerEarly:
                "Hold activates when another key is pressed (home-row mods)"
            case .quickTap:
                "Fast taps always register as tap"
            case .customKeys:
                "Only specific keys trigger early tap"
            }
        }
    }

    /// The configured hold behavior type
    @Published public var holdBehavior: HoldBehaviorType = .basic

    /// The action to perform when key is held (e.g., "lmet" for Command)
    @Published public var holdAction: String = ""

    /// Custom keys that trigger tap for customKeys behavior
    @Published public var customTapKeysText: String = ""

    /// Whether advanced section is expanded
    @Published public var showAdvanced = false

    // MARK: - Tap-Dance

    /// Double tap action
    @Published public var doubleTapAction: String = ""

    /// Tap-dance steps beyond double tap (Triple Tap, Quad Tap, etc.)
    /// Each step has a label, action, and recording state
    @Published public var tapDanceSteps: [(label: String, action: String, isRecording: Bool)] = []

    /// Labels for tap-dance steps
    public static let tapDanceLabels = ["Triple Tap", "Quad Tap", "Quint Tap", "Sext Tap", "Sept Tap"]

    // MARK: - Timing

    /// Whether timing section is expanded
    @Published public var showTimingAdvanced = false

    /// Tap timeout in milliseconds
    @Published public var tapTimeout: Int = 200

    /// Hold timeout in milliseconds
    @Published public var holdTimeout: Int = 200

    /// Combined tapping term (legacy, uses tapTimeout value)
    public var tappingTerm: Int {
        get { tapTimeout }
        set { tapTimeout = newValue }
    }

    // MARK: - Recording State

    /// Whether currently recording hold action
    @Published public var isRecordingHold = false

    /// Whether currently recording double tap action
    @Published public var isRecordingDoubleTap = false

    // MARK: - Conflict Detection

    /// Type of conflict between hold and tap-dance
    public enum ConflictType: Sendable {
        case holdVsTapDance
    }

    /// Whether conflict dialog should be shown
    @Published public var showConflictDialog = false

    /// The type of pending conflict
    @Published public var pendingConflictType: ConflictType?

    /// The field that triggered the conflict ("hold", "doubleTap", or "tapDance-N")
    @Published public var pendingConflictField: String = ""

    // MARK: - Initialization

    public init() {}

    // MARK: - Tap-Dance Management

    /// Add next tap-dance step (Triple Tap, Quad Tap, etc.)
    public func addTapDanceStep() {
        let index = tapDanceSteps.count
        guard index < Self.tapDanceLabels.count else { return }
        let label = Self.tapDanceLabels[index]
        tapDanceSteps.append((label: label, action: "", isRecording: false))
    }

    /// Remove tap-dance step at index
    public func removeTapDanceStep(at index: Int) {
        guard index >= 0, index < tapDanceSteps.count else { return }
        tapDanceSteps.remove(at: index)
    }

    /// Clear tap-dance step action at index
    public func clearTapDanceStep(at index: Int) {
        guard index >= 0, index < tapDanceSteps.count else { return }
        tapDanceSteps[index].action = ""
    }

    // MARK: - Conflict Detection

    /// Check if setting hold would conflict with existing tap-dance
    public func checkHoldConflict() -> Bool {
        !doubleTapAction.isEmpty || tapDanceSteps.contains { !$0.action.isEmpty }
    }

    /// Check if setting tap-dance would conflict with existing hold
    public func checkTapDanceConflict() -> Bool {
        !holdAction.isEmpty
    }

    // MARK: - Conflict Resolution

    /// Resolve conflict by keeping hold (clears all tap-dance actions)
    public func resolveConflictKeepHold() {
        doubleTapAction = ""
        for i in tapDanceSteps.indices {
            tapDanceSteps[i].action = ""
        }
        showConflictDialog = false
        pendingConflictType = nil
        pendingConflictField = ""
    }

    /// Resolve conflict by keeping tap-dance (clears hold action)
    public func resolveConflictKeepTapDance() {
        holdAction = ""
        holdBehavior = .basic
        customTapKeysText = ""
        showConflictDialog = false
        pendingConflictType = nil
        pendingConflictField = ""
    }

    // MARK: - Recording Control

    /// Stop all recording states
    public func stopAllRecording() {
        isRecordingHold = false
        isRecordingDoubleTap = false
        for i in tapDanceSteps.indices {
            tapDanceSteps[i].isRecording = false
        }
    }

    /// Check if any recording is active
    public var isAnyRecording: Bool {
        isRecordingHold || isRecordingDoubleTap || tapDanceSteps.contains { $0.isRecording }
    }

    // MARK: - Reset

    /// Reset all advanced behavior state
    public func reset() {
        holdBehavior = .basic
        holdAction = ""
        customTapKeysText = ""
        doubleTapAction = ""
        tapDanceSteps.removeAll()
        tapTimeout = 200
        holdTimeout = 200
        showAdvanced = false
        showTimingAdvanced = false
        stopAllRecording()
        showConflictDialog = false
        pendingConflictType = nil
        pendingConflictField = ""
    }

    // MARK: - Has Advanced Config

    /// Whether any advanced behavior is configured
    public var hasAdvancedConfig: Bool {
        !holdAction.isEmpty ||
            !doubleTapAction.isEmpty ||
            tapDanceSteps.contains { !$0.action.isEmpty } ||
            holdBehavior != .basic
    }
}

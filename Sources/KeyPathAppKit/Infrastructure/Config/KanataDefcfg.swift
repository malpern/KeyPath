/// Single source of truth for the kanata `(defcfg ...)` header block.
///
/// Every config KeyPath writes — generated, repaired, validated, or recovered —
/// renders its `defcfg` through this type. Previously the header was hand-built in
/// at least four places that had drifted apart (notably whether `danger-enable-cmd`
/// and a consistent `process-unmapped-keys` value were present), which meant the
/// root daemon's command-execution posture depended on which code path last wrote
/// the file. Centralizing it here keeps those decisions in one auditable place.
///
/// The named factories below (`standard`, `minimalSafe`, `validationWrapper`,
/// `repairFallback`) encode the *intentional* differences between emitters so the
/// variation is explicit rather than accidental.
public struct KanataDefcfg: Sendable, Equatable {
    /// `process-unmapped-keys yes|no`.
    public var processUnmappedKeys: Bool
    /// Emits `danger-enable-cmd yes` when true; omits the line entirely when false.
    /// This is the single switch that decides whether the root daemon will run
    /// `cmd` actions named in the config.
    public var allowCommandActions: Bool
    /// `managed-repeat yes|no` — omitted when nil.
    public var managedRepeat: Bool?
    /// `managed-repeat-unlisted yes|no` — omitted when nil.
    public var managedRepeatUnlisted: Bool?
    /// `managed-repeat-delay <ms>` — omitted when nil.
    public var managedRepeatDelayMs: Int?
    /// `managed-repeat-interval <ms>` — omitted when nil.
    public var managedRepeatIntervalMs: Int?
    /// `tap-hold-require-prior-idle <ms>` — omitted when nil.
    public var tapHoldRequirePriorIdleMs: Int?
    /// Emits `concurrent-tap-hold yes` when true. Kanata requires this whenever a
    /// `defchordsv2` block is present, otherwise it rejects the config.
    public var concurrentTapHold: Bool
    /// Verbatim text appended inside the `defcfg` block before the closing paren
    /// (e.g. the macOS device-targeting lines). Must already carry its own leading
    /// newline/indentation.
    public var trailer: String

    public init(
        processUnmappedKeys: Bool,
        allowCommandActions: Bool,
        managedRepeat: Bool? = nil,
        managedRepeatUnlisted: Bool? = nil,
        managedRepeatDelayMs: Int? = nil,
        managedRepeatIntervalMs: Int? = nil,
        tapHoldRequirePriorIdleMs: Int? = nil,
        concurrentTapHold: Bool = false,
        trailer: String = ""
    ) {
        self.processUnmappedKeys = processUnmappedKeys
        self.allowCommandActions = allowCommandActions
        self.managedRepeat = managedRepeat
        self.managedRepeatUnlisted = managedRepeatUnlisted
        self.managedRepeatDelayMs = managedRepeatDelayMs
        self.managedRepeatIntervalMs = managedRepeatIntervalMs
        self.tapHoldRequirePriorIdleMs = tapHoldRequirePriorIdleMs
        self.concurrentTapHold = concurrentTapHold
        self.trailer = trailer
    }

    /// Render the `(defcfg ... )` block. Each option line is indented two spaces.
    public func render() -> String {
        var lines = ["  process-unmapped-keys \(processUnmappedKeys ? "yes" : "no")"]
        if allowCommandActions {
            lines.append("  danger-enable-cmd yes")
        }
        if let managedRepeat {
            lines.append("  managed-repeat \(managedRepeat ? "yes" : "no")")
        }
        if let managedRepeatUnlisted {
            lines.append("  managed-repeat-unlisted \(managedRepeatUnlisted ? "yes" : "no")")
        }
        if let managedRepeatDelayMs {
            lines.append("  managed-repeat-delay \(managedRepeatDelayMs)")
        }
        if let managedRepeatIntervalMs {
            lines.append("  managed-repeat-interval \(managedRepeatIntervalMs)")
        }
        if let tapHoldRequirePriorIdleMs {
            lines.append("  tap-hold-require-prior-idle \(tapHoldRequirePriorIdleMs)")
        }
        if concurrentTapHold {
            lines.append("  concurrent-tap-hold yes")
        }
        return "(defcfg\n" + lines.joined(separator: "\n") + trailer + "\n)"
    }
}

public extension KanataDefcfg {
    /// The full runtime header used for generated user configs (rule collections).
    ///
    /// - Parameters:
    ///   - allowCommandActions: whether to emit `danger-enable-cmd yes`.
    ///   - managedRepeatDelayMs / managedRepeatIntervalMs: emitted only when non-nil
    ///     (the caller passes nil when key-repeat control is absent or disabled).
    ///   - requirePriorIdleMs: emitted as `tap-hold-require-prior-idle` when > 0.
    ///   - hasChords: emits `concurrent-tap-hold yes` (required by `defchordsv2`).
    ///   - deviceTargeting: verbatim macOS device-targeting trailer ("" when none).
    static func standard(
        allowCommandActions: Bool,
        managedRepeatDelayMs: Int?,
        managedRepeatIntervalMs: Int?,
        requirePriorIdleMs: Int,
        hasChords: Bool,
        deviceTargeting: String
    ) -> KanataDefcfg {
        KanataDefcfg(
            processUnmappedKeys: true,
            allowCommandActions: allowCommandActions,
            managedRepeat: true,
            managedRepeatUnlisted: false,
            managedRepeatDelayMs: managedRepeatDelayMs,
            managedRepeatIntervalMs: managedRepeatIntervalMs,
            tapHoldRequirePriorIdleMs: requirePriorIdleMs > 0 ? requirePriorIdleMs : nil,
            concurrentTapHold: hasChords,
            trailer: deviceTargeting
        )
    }

    /// Crash-loop recovery fallback written after a rollback failure.
    /// Intentionally omits command execution and repeat tuning — recovery must never
    /// (re)enable `cmd` actions or fail validation on optional tuning.
    static let minimalSafe = KanataDefcfg(
        processUnmappedKeys: true,
        allowCommandActions: false
    )

    /// Throwaway header used only to validate include files (`keypath-apps.kbd`),
    /// which are not standalone and need minimal `defcfg`/`defsrc` context.
    static let validationWrapper = KanataDefcfg(
        processUnmappedKeys: true,
        allowCommandActions: false
    )

    /// Minimal header injected by rule-based repair when a config is missing its
    /// `defcfg` entirely. Mirrors the generator's command-execution posture.
    static let repairFallback = KanataDefcfg(
        processUnmappedKeys: true,
        allowCommandActions: true
    )
}

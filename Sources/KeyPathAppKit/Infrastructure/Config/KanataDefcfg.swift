/// Single source of truth for the kanata `(defcfg ...)` header block.
///
/// Every config KeyPath writes — generated, repaired, validated, or recovered —
/// renders its `defcfg` through this type. Previously the header was hand-built in
/// at least four places that had drifted apart, which meant safety-relevant header
/// options depended on which code path last wrote the file. Centralizing it here
/// keeps those decisions in one auditable place.
///
/// `danger-enable-cmd` is deliberately not representable here: the bundled engine
/// is compiled WITHOUT kanata's `cmd` feature (issue #879), so the grant would be
/// meaningless — `(cmd ...)` actions fail at parse regardless of the header. If a
/// future emitter needs the line back, the engine build, this type, and the
/// DefcfgEmitterLintTests guard must change together, deliberately.
///
/// The named factories below (`standard`, `minimalSafe`, `validationWrapper`,
/// `repairFallback`) encode the *intentional* differences between emitters so the
/// variation is explicit rather than accidental.
public struct KanataDefcfg: Sendable, Equatable {
    /// `process-unmapped-keys yes|no`.
    public var processUnmappedKeys: Bool
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
        managedRepeat: Bool? = nil,
        managedRepeatUnlisted: Bool? = nil,
        managedRepeatDelayMs: Int? = nil,
        managedRepeatIntervalMs: Int? = nil,
        tapHoldRequirePriorIdleMs: Int? = nil,
        concurrentTapHold: Bool = false,
        trailer: String = ""
    ) {
        self.processUnmappedKeys = processUnmappedKeys
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
        // `trailer` is spliced verbatim before the closing paren, so a non-empty
        // trailer that doesn't start with a newline would weld onto the last option
        // line and emit invalid kanata. The only producer (device targeting) already
        // satisfies this; assert so a future producer can't violate it silently.
        assert(trailer.isEmpty || trailer.hasPrefix("\n"),
               "KanataDefcfg.trailer must begin with a newline when non-empty")
        // managed-repeat delay/interval are a logical pair; emitting one without the
        // other yields a half-configured block kanata may reject. The `standard`
        // factory enforces this structurally (single tuple param); this backstops the
        // internal `init`. assert() is debug-only, which is sufficient for that path.
        assert((managedRepeatDelayMs == nil) == (managedRepeatIntervalMs == nil),
               "managed-repeat delay and interval must both be set or both be nil")
        var lines = ["  process-unmapped-keys \(processUnmappedKeys ? "yes" : "no")"]
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
    ///   - managedRepeatTiming: the `(delay, interval)` pair, or nil to omit both.
    ///     Taken as a single tuple so delay and interval can never be half-set at this
    ///     entry point (the `render()` assert backstops the internal `init`).
    ///   - requirePriorIdleMs: `tap-hold-require-prior-idle` value, or nil to omit.
    ///     The caller maps its "0 means disabled" sentinel to nil.
    ///   - hasChords: emits `concurrent-tap-hold yes` (required by `defchordsv2`).
    ///   - deviceTargeting: verbatim macOS device-targeting trailer ("" when none).
    ///
    /// `managed-repeat`/`managed-repeat-unlisted` are always emitted; when
    /// `managedRepeatTiming` is nil, kanata uses its own defaults for delay/interval.
    static func standard(
        managedRepeatTiming: (delayMs: Int, intervalMs: Int)?,
        requirePriorIdleMs: Int?,
        hasChords: Bool,
        deviceTargeting: String
    ) -> KanataDefcfg {
        KanataDefcfg(
            processUnmappedKeys: true,
            managedRepeat: true,
            managedRepeatUnlisted: false,
            managedRepeatDelayMs: managedRepeatTiming?.delayMs,
            managedRepeatIntervalMs: managedRepeatTiming?.intervalMs,
            tapHoldRequirePriorIdleMs: requirePriorIdleMs,
            concurrentTapHold: hasChords,
            trailer: deviceTargeting
        )
    }

    /// Crash-loop recovery fallback written after a rollback failure.
    /// Intentionally omits repeat tuning — recovery must never fail validation on
    /// optional tuning.
    ///
    /// Currently renders identically to `validationWrapper` and `repairFallback`;
    /// the separate names preserve the option to diverge and document the distinct
    /// call sites.
    static let minimalSafe = KanataDefcfg(
        processUnmappedKeys: true
    )

    /// Throwaway header used only to validate include files (`keypath-apps.kbd`),
    /// which are not standalone and need minimal `defcfg`/`defsrc` context.
    /// Renders identically to `minimalSafe` today; see that profile's note.
    static let validationWrapper = KanataDefcfg(
        processUnmappedKeys: true
    )

    /// Minimal header injected by rule-based repair when a config is missing its
    /// `defcfg` entirely. Renders identically to `minimalSafe` today; see that
    /// profile's note.
    static let repairFallback = KanataDefcfg(
        processUnmappedKeys: true
    )
}

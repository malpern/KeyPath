/// The key managed Caps Lock travels as between the hidutil substitution and
/// the session's event tap. It is reserved while managed Caps runs: the tap
/// cannot tell a substituted Caps press from that key pressed natively.
///
/// The pool is F13–F20, the function keys the event tap can see. F21–F24 have
/// no macOS virtual keycode, so a substitution to them never reaches the tap.
/// The current choice is kept while it stays free; F18 is tried first because
/// it was the only intermediate before this became a choice.
public enum SessionCapsIntermediate {
    /// Keyboard-page usage IDs, in preference order.
    public static let pool: [UInt32] = [109, 110, 111, 104, 105, 106, 107, 108]
    public static let defaultUsage: UInt32 = 109

    /// macOS virtual keycodes, as the event tap reports them.
    public static let keyCodes: [UInt32: UInt16] = [
        104: 105, 105: 107, 106: 113, 107: 106, 108: 64, 109: 79, 110: 80, 111: 90
    ]

    public static func isCandidate(_ usage: UInt32) -> Bool {
        keyCodes[usage] != nil
    }

    public static func isCandidate(packed: UInt64) -> Bool {
        packed >> 32 == 7 && isCandidate(UInt32(packed & 0xFFFF_FFFF))
    }

    /// "F18" for display.
    public static func label(_ usage: UInt32) -> String {
        "F\(Int(usage) - 104 + 13)"
    }

    /// "f18" for Kanata configuration text.
    public static func kanataName(_ usage: UInt32) -> String {
        label(usage).lowercased()
    }

    /// Every pool key that an existing UserKeyMapping row (any service, either
    /// side) or an enabled macOS keyboard shortcut already uses. Rows KeyPath
    /// itself leased are the caller's to exclude before asking.
    public static func occupied(mappingUsages: [UInt64], shortcutKeyCodes: Set<UInt16>) -> Set<UInt32> {
        var taken = Set<UInt32>()
        for usage in pool {
            if mappingUsages.contains(SessionCapsMappingPolicy.packed(usage)) { taken.insert(usage) }
            if let code = keyCodes[usage], shortcutKeyCodes.contains(code) { taken.insert(usage) }
        }
        return taken
    }

    /// The first free key the profile also accepts, preferring `preferred`.
    /// `acceptsProfile` reports whether the user's rules leave that key alone;
    /// nil when no candidate is both free and unused.
    public static func choose(preferred: UInt32?, occupied: Set<UInt32>,
                              acceptsProfile: (UInt32) -> Bool) -> UInt32?
    {
        var order = pool
        if let preferred, isCandidate(preferred) {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        return order.first { !occupied.contains($0) && acceptsProfile($0) }
    }
}

/// Who else is mapping Caps Lock on a keyboard, when that can be told.
/// Identification needs both the mapping row and the owner's own setting:
/// a destination alone does not name an app.
public enum SessionCapsConflict: Equatable, Sendable {
    /// Raycast's Hyper Key. Witnessed 2026-10-19: `com.raycast.macos
    /// raycast_hyperKey_state` {enabled=1, keyCode=57} maps Caps (0x700000039)
    /// to F20 (0x70000006F) on every keyboard service.
    case raycastHyperKey
    /// Something else maps Caps Lock to this packed destination usage.
    case unknown(destination: UInt64)

    /// Raycast's preference as read from its defaults domain.
    public struct RaycastHyperKey: Equatable, Sendable {
        public let enabled: Bool
        public let keyCode: Int?
        public init(enabled: Bool, keyCode: Int?) {
            self.enabled = enabled
            self.keyCode = keyCode
        }
    }

    /// nil when no row maps Caps Lock.
    public static func identify(_ mappings: [SessionCapsMappingPolicy.Mapping],
                                raycast: RaycastHyperKey?) -> SessionCapsConflict?
    {
        guard let row = mappings.first(where: { $0.source == SessionCapsMappingPolicy.caps }) else { return nil }
        // Raycast's Hyper Key keyCode is the macOS virtual keycode of the
        // trigger: 57 is Caps Lock. Its hidutil destination is F20.
        if let raycast, raycast.enabled, raycast.keyCode == 57, row.destination == 0x7_0000_006F {
            return .raycastHyperKey
        }
        return .unknown(destination: row.destination)
    }

    /// The packed usage Caps Lock is mapped to.
    public var destination: UInt64 {
        switch self {
        case .raycastHyperKey: 0x7_0000_006F
        case let .unknown(destination): destination
        }
    }

    public var message: String {
        switch self {
        case .raycastHyperKey:
            "Raycast\u{2019}s Hyper Key is using Caps Lock. Turn it off in Raycast, or use another trigger for Hyper Key."
        case let .unknown(destination):
            if destination >> 32 == 7, SessionCapsIntermediate.isCandidate(UInt32(destination & 0xFFFF_FFFF)) {
                "Another app is already remapping Caps Lock on this keyboard (to \(SessionCapsIntermediate.label(UInt32(destination & 0xFFFF_FFFF)))). Turn that off to use Caps Lock rules in KeyPath."
            } else {
                "Another app or the Modifier Keys setting in System Settings is already remapping Caps Lock on this keyboard. Turn that off to use Caps Lock rules in KeyPath."
            }
        }
    }
}

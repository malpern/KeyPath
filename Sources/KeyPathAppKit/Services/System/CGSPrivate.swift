import AppKit
import Foundation
import KeyPathCore

// MARK: - CoreGraphics Services (CGS) Private API

// Private API declarations for macOS Space management.
// These are undocumented but stable APIs used by apps like Amethyst, alt-tab-macos, and yabai.
//
// ## References
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/Spaces.swift
// - https://github.com/ianyh/Amethyst
// - https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h
//
// ## Stability
// These APIs have been stable across macOS versions but are subject to change without notice.
// The notarization process does not block private API usage (only App Store review does).
//
// ## Availability Detection
// Every symbol is resolved with `dlsym` (see `CGSFunctions`), so the app has no
// link-time dependency on them. `CGSPrivateAPI.isAvailable` reports whether all resolved.

// MARK: - Type Aliases

public typealias CGSConnectionID = UInt32
public typealias CGSSpaceID = UInt64

// MARK: - CGS Function Pointers

// These symbols are resolved at runtime with `dlsym`, never linked directly.
// A direct declaration (`@_silgen_name`) makes the linker emit a strong
// undefined import, and dyld then refuses to launch the app if a future
// macOS removes any one of them. Resolving them here means a missing symbol
// only disables Space management (see `CGSPrivateAPI.isAvailable`).

/// Typed function pointers for the private CGS / AX calls KeyPath uses.
/// Exists only when every symbol resolved.
struct CGSFunctions {
    typealias MainConnectionID = @convention(c) () -> CGSConnectionID
    typealias ManagedDisplayGetCurrentSpace = @convention(c) (CGSConnectionID, CFString) -> CGSSpaceID
    /// Follows the Copy rule: the returned array is +1.
    typealias CopyManagedDisplaySpaces = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    typealias WindowsSpaces = @convention(c) (CGSConnectionID, CFArray, CFArray) -> Void
    /// Follows the Copy rule: the returned array is +1.
    typealias CopySpacesForWindows = @convention(c) (CGSConnectionID, Int, CFArray) -> Unmanaged<CFArray>?
    typealias AXUIElementGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Get the main connection ID for the current process
    let mainConnectionID: MainConnectionID
    /// Get the currently active space on the specified display
    let managedDisplayGetCurrentSpace: ManagedDisplayGetCurrentSpace
    /// Copy information about all managed displays and their spaces
    let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    /// Add windows to specified spaces
    let addWindowsToSpaces: WindowsSpaces
    /// Remove windows from specified spaces
    let removeWindowsFromSpaces: WindowsSpaces
    /// Get the spaces a set of windows are on
    let copySpacesForWindows: CopySpacesForWindows
    /// Get the CGWindowID for an AXUIElement window. Bridges the Accessibility
    /// API to CGS, allowing direct lookup instead of enumerating every window
    /// via CGWindowListCopyWindowInfo.
    let axUIElementGetWindow: AXUIElementGetWindow

    /// Look a symbol up in the images already loaded into the process
    /// (`RTLD_DEFAULT`). CoreGraphics and ApplicationServices are loaded by AppKit.
    static func dlsymLookup(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    /// Resolve every symbol. Returns nil plus the names that did not resolve
    /// when any is missing; never traps. `lookup` is injectable for tests.
    static func resolve(
        lookup: (String) -> UnsafeMutableRawPointer? = dlsymLookup
    ) -> (functions: CGSFunctions?, missing: [String]) {
        var missing: [String] = []
        func load<T>(_ name: String, as _: T.Type) -> T? {
            guard let pointer = lookup(name) else {
                missing.append(name)
                return nil
            }
            return unsafeBitCast(pointer, to: T.self)
        }

        let mainConnectionID = load("CGSMainConnectionID", as: MainConnectionID.self)
        let copyManagedDisplaySpaces = load("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpaces.self)
        let managedDisplayGetCurrentSpace = load(
            "CGSManagedDisplayGetCurrentSpace", as: ManagedDisplayGetCurrentSpace.self
        )
        let addWindowsToSpaces = load("CGSAddWindowsToSpaces", as: WindowsSpaces.self)
        let removeWindowsFromSpaces = load("CGSRemoveWindowsFromSpaces", as: WindowsSpaces.self)
        let copySpacesForWindows = load("CGSCopySpacesForWindows", as: CopySpacesForWindows.self)
        let axUIElementGetWindow = load("_AXUIElementGetWindow", as: AXUIElementGetWindow.self)

        guard let mainConnectionID,
              let copyManagedDisplaySpaces,
              let managedDisplayGetCurrentSpace,
              let addWindowsToSpaces,
              let removeWindowsFromSpaces,
              let copySpacesForWindows,
              let axUIElementGetWindow
        else {
            return (nil, missing)
        }
        let functions = CGSFunctions(
            mainConnectionID: mainConnectionID,
            managedDisplayGetCurrentSpace: managedDisplayGetCurrentSpace,
            copyManagedDisplaySpaces: copyManagedDisplaySpaces,
            addWindowsToSpaces: addWindowsToSpaces,
            removeWindowsFromSpaces: removeWindowsFromSpaces,
            copySpacesForWindows: copySpacesForWindows,
            axUIElementGetWindow: axUIElementGetWindow
        )
        return (functions, [])
    }
}

// MARK: - Space Mask Constants

/// Mask for querying all spaces
let kCGSAllSpacesMask: Int = 0x7

// MARK: - API Availability Detection

/// Checks availability of private CGS APIs at runtime.
/// Use this to gracefully degrade if Apple changes or removes these APIs.
public enum CGSPrivateAPI {
    /// Cached resolution: nil until checked; `.some(nil)` when a symbol is missing.
    /// Guarded by `lock`: the value holds function pointers, so a torn read
    /// would be a call through garbage.
    private nonisolated(unsafe) static var cachedFunctions: CGSFunctions??
    private static let lock = NSLock()

    /// The resolved function pointers, or nil when any symbol is missing.
    /// Every call into the private APIs goes through this, so a missing symbol
    /// can never be called.
    static var functions: CGSFunctions? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedFunctions {
            return cached
        }
        let (functions, missing) = CGSFunctions.resolve()
        if functions == nil {
            AppLogger.shared.log("⚠️ [CGSPrivateAPI] Missing symbols: \(missing.joined(separator: ", "))")
            AppLogger.shared.log("⚠️ [CGSPrivateAPI] Space movement features will be disabled")
        } else {
            AppLogger.shared.log("✅ [CGSPrivateAPI] All required symbols available")
        }
        cachedFunctions = .some(functions)
        return functions
    }

    /// Whether all required CGS APIs resolved to callable function pointers.
    public static var isAvailable: Bool {
        functions != nil
    }

    /// Reset the availability cache to force a re-check.
    /// Used by retry logic when APIs may become available after startup.
    public static func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedFunctions = nil
    }

    /// Detailed availability check with per-symbol results
    public static func checkAvailabilityDetails() -> (available: Bool, missing: [String]) {
        let (functions, missing) = CGSFunctions.resolve()
        return (functions != nil, missing)
    }

    /// Human-readable status for UI display
    public static var statusMessage: String {
        if isAvailable {
            return "Space management APIs available"
        } else {
            let (_, missing) = checkAvailabilityDetails()
            return "Space management unavailable (missing: \(missing.joined(separator: ", ")))"
        }
    }
}

// MARK: - Space Manager

/// Manages macOS Spaces (virtual desktops) using private CoreGraphics Services APIs.
///
/// ## Usage
/// ```swift
/// // Check availability first
/// guard SpaceManager.shared.isAvailable else {
///     print("Space features not available on this macOS version")
///     return
/// }
///
/// let manager = SpaceManager.shared
/// if let nextSpace = manager.nextSpaceID() {
///     manager.moveWindow(windowID, to: nextSpace)
/// }
/// ```
public final class SpaceManager {
    // MARK: - Singleton

    @MainActor public static let shared = SpaceManager()

    // MARK: - Availability

    /// Whether Space management APIs are available on this system.
    /// Check this before calling any Space-related methods.
    public var isAvailable: Bool {
        CGSPrivateAPI.isAvailable
    }

    /// Human-readable status message for UI display
    public var statusMessage: String {
        CGSPrivateAPI.statusMessage
    }

    // MARK: - State

    /// Ordered list of space IDs for the main display
    private var spaceIDs: [CGSSpaceID] = []

    /// Current space ID
    private var currentSpaceID: CGSSpaceID = 0

    /// CGS connection ID (cached)
    private var connectionID: CGSConnectionID = 0

    /// Whether initialization was deferred due to API unavailability
    private var initializationDeferred = false

    // MARK: - Initialization

    private init() {
        // Only initialize if APIs are available
        if let functions = CGSPrivateAPI.functions {
            connectionID = functions.mainConnectionID()
            refreshSpaces()
        } else {
            initializationDeferred = true
            AppLogger.shared.log("⚠️ [SpaceManager] Initialized in degraded mode - CGS APIs unavailable at startup, will retry")
        }
    }

    // MARK: - Retry Logic

    /// Retry initialization if it was deferred. Called by WindowManager after app startup.
    /// - Returns: true if APIs are now available, false otherwise
    @discardableResult
    public func retryInitialization() -> Bool {
        guard initializationDeferred else {
            // Already initialized successfully
            return isAvailable
        }

        // Force re-check of API availability
        CGSPrivateAPI.resetCache()
        if let functions = CGSPrivateAPI.functions {
            connectionID = functions.mainConnectionID()
            refreshSpaces()
            initializationDeferred = false
            AppLogger.shared.log("✅ [SpaceManager] Retry successful - CGS APIs now available")
            return true
        } else {
            AppLogger.shared.log("⚠️ [SpaceManager] Retry failed - CGS APIs still unavailable")
            return false
        }
    }

    // MARK: - Public API

    /// Refresh the list of spaces from the system
    public func refreshSpaces() {
        guard let functions = CGSPrivateAPI.functions else { return }
        guard let displaysInfo = functions.copyManagedDisplaySpaces(connectionID)?
            .takeRetainedValue() as? [[String: Any]]
        else {
            AppLogger.shared.log("⚠️ [SpaceManager] Failed to get display spaces")
            return
        }

        // Get the main display's spaces
        // The first display in the array is typically the main display
        guard let mainDisplay = displaysInfo.first,
              let spaces = mainDisplay["Spaces"] as? [[String: Any]]
        else {
            AppLogger.shared.log("⚠️ [SpaceManager] No spaces found for main display")
            return
        }

        // Extract space IDs in order
        spaceIDs = spaces.compactMap { space -> CGSSpaceID? in
            // Space type 0 = regular desktop, type 4 = fullscreen app
            guard let type = space["type"] as? Int, type == 0 else {
                return nil
            }
            return space["ManagedSpaceID"] as? CGSSpaceID ?? space["id64"] as? CGSSpaceID
        }

        // Get current space
        if let displayUUID = mainDisplay["Display Identifier"] as? String {
            currentSpaceID = functions.managedDisplayGetCurrentSpace(connectionID, displayUUID as CFString)
        }

        AppLogger.shared.log("🪟 [SpaceManager] Refreshed: \(spaceIDs.count) spaces, current: \(currentSpaceID)")
    }

    /// Get the current space index (1-based for user display)
    public var currentSpaceIndex: Int? {
        guard let index = spaceIDs.firstIndex(of: currentSpaceID) else {
            return nil
        }
        return index + 1
    }

    /// Get the space ID for the next space (wraps around)
    public func nextSpaceID() -> CGSSpaceID? {
        guard isAvailable else {
            AppLogger.shared.log("⚠️ [SpaceManager] nextSpaceID: CGS APIs unavailable")
            return nil
        }
        refreshSpaces() // Ensure fresh data
        guard !spaceIDs.isEmpty else { return nil }
        guard let currentIndex = spaceIDs.firstIndex(of: currentSpaceID) else {
            return spaceIDs.first
        }
        let nextIndex = (currentIndex + 1) % spaceIDs.count
        return spaceIDs[nextIndex]
    }

    /// Get the space ID for the previous space (wraps around)
    public func previousSpaceID() -> CGSSpaceID? {
        guard isAvailable else {
            AppLogger.shared.log("⚠️ [SpaceManager] previousSpaceID: CGS APIs unavailable")
            return nil
        }
        refreshSpaces() // Ensure fresh data
        guard !spaceIDs.isEmpty else { return nil }
        guard let currentIndex = spaceIDs.firstIndex(of: currentSpaceID) else {
            return spaceIDs.last
        }
        let prevIndex = (currentIndex - 1 + spaceIDs.count) % spaceIDs.count
        return spaceIDs[prevIndex]
    }

    /// Move a window to a specific space
    /// - Parameters:
    ///   - windowID: The CGWindowID of the window to move
    ///   - spaceID: The target space ID
    /// - Returns: true if successful
    @discardableResult
    public func moveWindow(_ windowID: CGWindowID, to spaceID: CGSSpaceID) -> Bool {
        guard let functions = CGSPrivateAPI.functions else {
            AppLogger.shared.log("⚠️ [SpaceManager] moveWindow: CGS APIs unavailable")
            return false
        }

        // Get the window's current space
        let windowIDs = [windowID] as CFArray
        guard let currentSpaces = functions.copySpacesForWindows(connectionID, kCGSAllSpacesMask, windowIDs)?
            .takeRetainedValue() as? [CGSSpaceID],
            let currentSpace = currentSpaces.first
        else {
            AppLogger.shared.log("⚠️ [SpaceManager] Could not get current space for window \(windowID)")
            return false
        }

        // Remove from current space
        functions.removeWindowsFromSpaces(connectionID, windowIDs, [currentSpace] as CFArray)

        // Add to target space
        functions.addWindowsToSpaces(connectionID, windowIDs, [spaceID] as CFArray)

        AppLogger.shared.log("✅ [SpaceManager] Moved window \(windowID) from space \(currentSpace) to \(spaceID)")
        return true
    }

    /// Get the window ID for the frontmost window of the frontmost app
    public func getFrontmostWindowID() -> CGWindowID? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier

        // Get windows for this process
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the frontmost window belonging to this app
        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == pid,
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 // Normal window layer
            else {
                continue
            }
            return windowID
        }

        return nil
    }
}

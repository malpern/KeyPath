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
// Use `CGSPrivateAPI.isAvailable` to check if the APIs are accessible before use.

// MARK: - Type Aliases

public typealias CGSConnectionID = UInt32
public typealias CGSSpaceID = UInt64

// MARK: - CGS Function Declarations

/// Get the main connection ID for the current process
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// Get the currently active space on the specified display
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ connection: CGSConnectionID, _ displayUUID: CFString) -> CGSSpaceID

/// Copy information about all managed displays and their spaces
/// Returns an array of dictionaries with display and space information
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray

/// Add windows to specified spaces
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

/// Remove windows from specified spaces
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

/// Get the space ID for windows
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ connection: CGSConnectionID, _ mask: Int, _ windowIDs: CFArray) -> CFArray

// MARK: - AXUIElement Private Extensions

/// Get the CGWindowID for an AXUIElement window.
/// This bridges the Accessibility API world to the CoreGraphics Services world,
/// allowing direct lookup instead of enumerating all windows via CGWindowListCopyWindowInfo.
///
/// ## Usage
/// ```swift
/// let axWindow: AXUIElement = // ... from AXUIElementCopyAttributeValue
/// var windowID: CGWindowID = 0
/// if _AXUIElementGetWindow(axWindow, &windowID) == .success {
///     SpaceManager.shared.moveWindow(windowID, to: targetSpace)
/// }
/// ```
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

// MARK: - Space Mask Constants

/// Mask for querying all spaces
let kCGSAllSpacesMask: Int = 0x7

// MARK: - API Availability Detection

/// Checks availability of private CGS APIs at runtime.
/// Use this to gracefully degrade if Apple changes or removes these APIs.
public enum CGSPrivateAPI {
    /// Required symbol names for Space management
    private static let requiredSymbols = [
        "CGSMainConnectionID",
        "CGSCopyManagedDisplaySpaces",
        "CGSManagedDisplayGetCurrentSpace",
        "CGSAddWindowsToSpaces",
        "CGSRemoveWindowsFromSpaces",
        "CGSCopySpacesForWindows",
        "_AXUIElementGetWindow"
    ]

    /// Cache the availability check result
    nonisolated(unsafe) static var _isAvailable: Bool?

    /// Whether all required CGS APIs are available.
    /// This checks for symbol presence using dlsym at runtime.
    public static var isAvailable: Bool {
        if let cached = _isAvailable {
            return cached
        }

        let result = checkAvailability()
        _isAvailable = result
        return result
    }

    /// Reset the availability cache to force a re-check.
    /// Used by retry logic when APIs may become available after startup.
    public static func resetCache() {
        _isAvailable = nil
    }

    /// Detailed availability check with per-symbol results
    public static func checkAvailabilityDetails() -> (available: Bool, missing: [String]) {
        var missing: [String] = []

        for symbol in requiredSymbols {
            if dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) == nil {
                missing.append(symbol)
            }
        }

        return (missing.isEmpty, missing)
    }

    private static func checkAvailability() -> Bool {
        let (available, missing) = checkAvailabilityDetails()

        if !available {
            AppLogger.shared.log("⚠️ [CGSPrivateAPI] Missing symbols: \(missing.joined(separator: ", "))")
            AppLogger.shared.log("⚠️ [CGSPrivateAPI] Space movement features will be disabled")
        } else {
            AppLogger.shared.log("✅ [CGSPrivateAPI] All required symbols available")
        }

        return available
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
@MainActor
public final class SpaceManager {
    // MARK: - Singleton

    public static let shared = SpaceManager()

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
        if CGSPrivateAPI.isAvailable {
            connectionID = CGSMainConnectionID()
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
        let nowAvailable = CGSPrivateAPI.isAvailable

        if nowAvailable {
            connectionID = CGSMainConnectionID()
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
        guard isAvailable else { return }
        guard let displaysInfo = CGSCopyManagedDisplaySpaces(connectionID) as? [[String: Any]] else {
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
            currentSpaceID = CGSManagedDisplayGetCurrentSpace(connectionID, displayUUID as CFString)
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
        guard isAvailable else {
            AppLogger.shared.log("⚠️ [SpaceManager] moveWindow: CGS APIs unavailable")
            return false
        }

        // Get the window's current space
        let windowIDs = [windowID] as CFArray
        guard let currentSpaces = CGSCopySpacesForWindows(connectionID, kCGSAllSpacesMask, windowIDs) as? [CGSSpaceID],
              let currentSpace = currentSpaces.first
        else {
            AppLogger.shared.log("⚠️ [SpaceManager] Could not get current space for window \(windowID)")
            return false
        }

        // Remove from current space
        CGSRemoveWindowsFromSpaces(connectionID, windowIDs, [currentSpace] as CFArray)

        // Add to target space
        CGSAddWindowsToSpaces(connectionID, windowIDs, [spaceID] as CFArray)

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

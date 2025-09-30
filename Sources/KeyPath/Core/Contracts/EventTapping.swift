import CoreGraphics
import Foundation

/// A handle representing an installed event tap that can be used for cleanup.
public struct TapHandle {
    let machPort: CFMachPort
    let runLoopSource: CFRunLoopSource?
}

/// Protocol defining event tap installation and management capabilities.
///
/// This protocol provides a clean interface for installing, managing, and removing
/// CGEvent taps within KeyPath. It abstracts the low-level CoreGraphics event tap
/// mechanics behind a service-oriented interface.
///
/// ## Usage
///
/// Event tap services should implement this protocol to provide consistent
/// tap lifecycle management:
///
/// ```swift
/// class KeyboardTapService: EventTapping {
///     private var currentTap: TapHandle?
///
///     var isInstalled: Bool {
///         return currentTap != nil
///     }
///
///     func install() throws -> TapHandle {
///         guard !isInstalled else { throw TapError.alreadyInstalled }
///
///         // Create CGEvent tap
///         let tap = CGEvent.tapCreate(...)
///         let source = CFMachPortCreateRunLoopSource(...)
///
///         let handle = TapHandle(machPort: tap, runLoopSource: source)
///         currentTap = handle
///         return handle
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations should ensure thread-safe access to tap state and handle
/// concurrent install/uninstall operations appropriately.
///
/// ## Permissions
///
/// Event tap installation requires appropriate system permissions (Accessibility
/// or Input Monitoring). Implementations should provide clear error messages
/// when permissions are insufficient.
protocol EventTapping {
    /// Indicates whether an event tap is currently installed and active.
    ///
    /// This property should accurately reflect the tap's operational state.
    var isInstalled: Bool { get }

    /// Installs and activates an event tap.
    ///
    /// Creates the necessary CGEvent tap, configures run loop integration,
    /// and returns a handle for later cleanup.
    ///
    /// - Returns: A `TapHandle` representing the installed tap.
    /// - Throws: `TapError` if installation fails or tap already exists.
    func install() throws -> TapHandle

    /// Removes and deactivates the currently installed event tap.
    ///
    /// Cleans up CGEvent tap resources, removes run loop sources, and
    /// ensures proper resource deallocation.
    ///
    /// This method should be idempotent - calling it when no tap is installed
    /// should not cause errors.
    func uninstall()
}

/// Extension providing convenience methods for tap management.
extension EventTapping {
    /// Reinstalls the event tap by removing the old one and installing a new one.
    ///
    /// This is useful for recovering from tap failures or updating tap configuration.
    ///
    /// - Returns: A new `TapHandle` representing the reinstalled tap.
    /// - Throws: `TapError` if reinstallation fails.
    func reinstall() throws -> TapHandle {
        uninstall()
        return try install()
    }

    /// Ensures the event tap is in the desired installation state.
    ///
    /// - Parameter shouldBeInstalled: The desired installation state.
    /// - Returns: A `TapHandle` if a tap was installed, nil otherwise.
    /// - Throws: `TapError` if state change fails.
    func ensureState(installed shouldBeInstalled: Bool) throws -> TapHandle? {
        if shouldBeInstalled, !isInstalled {
            return try install()
        } else if !shouldBeInstalled, isInstalled {
            uninstall()
            return nil
        }
        return nil
    }
}

/// Errors related to event tap operations.
/// Event tap errors
///
/// - Deprecated: Use `KeyPathError.system(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.system(...) instead")
enum TapError: Error, LocalizedError {
    case alreadyInstalled
    case notInstalled
    case permissionDenied
    case creationFailed(String)
    case runLoopError
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .alreadyInstalled:
            "Event tap is already installed"
        case .notInstalled:
            "No event tap is currently installed"
        case .permissionDenied:
            "Insufficient permissions to create event tap"
        case let .creationFailed(reason):
            "Failed to create event tap: \(reason)"
        case .runLoopError:
            "Failed to configure run loop for event tap"
        case .invalidConfiguration:
            "Invalid event tap configuration"
        }
    }

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case .alreadyInstalled:
            return .system(.eventTapCreationFailed)
        case .notInstalled:
            return .system(.eventTapCreationFailed)
        case .permissionDenied:
            return .permission(.accessibilityNotGranted)
        case let .creationFailed(reason):
            return .system(.eventTapCreationFailed)
        case .runLoopError:
            return .system(.eventTapEnableFailed)
        case .invalidConfiguration:
            return .system(.eventTapCreationFailed)
        }
    }
}

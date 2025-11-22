import AppKit
@preconcurrency import ApplicationServices
import Foundation
import IOKit.hid
import KeyPathCore

/// Centralized utilities for requesting system permissions using Apple's standard APIs.
/// - Requests are debounced to avoid nagging the user.
/// - Requests are only attempted when the app is foreground to ensure the prompt is visible.
@MainActor
final class PermissionRequestService {
    static let shared = PermissionRequestService()

    private init() {}

    // MARK: - Debounce (cooldown) configuration

    private let cooldownSeconds: TimeInterval = 20 * 60 // 20 minutes
    private let lastPromptIMKey = "permission_last_prompt_im"
    private let lastPromptAXKey = "permission_last_prompt_ax"

    private func isForeground() -> Bool {
        NSApplication.shared.isActive
    }

    private func ensureForeground() {
        if !NSApplication.shared.isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
            AppLogger.shared.info("ℹ️ [PermissionRequest] Activated app to foreground for system prompt")
        }
    }

    private func withinCooldown(_ key: String) -> Bool {
        let last = UserDefaults.standard.double(forKey: key)
        guard last > 0 else { return false }
        return (Date().timeIntervalSince1970 - last) < cooldownSeconds
    }

    private func markPrompt(_ key: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    // MARK: - Public API

    /// Request Input Monitoring permission using IOHIDRequestAccess().
    /// - Returns: true if already granted (no prompt shown), false otherwise.
    @discardableResult
    func requestInputMonitoringPermission(ignoreCooldown: Bool = false) -> Bool {
        // Foreground and cooldown guards
        ensureForeground()
        if !isForeground() {
            AppLogger.shared.warn(
                "⚠️ [PermissionRequest] Skipping IOHIDRequestAccess - app not foreground")
            return false
        }
        if !ignoreCooldown, withinCooldown(lastPromptIMKey) {
            AppLogger.shared.info("ℹ️ [PermissionRequest] Skipping IOHIDRequestAccess - within cooldown")
            return false
        }
        markPrompt(lastPromptIMKey)

        // IOHIDRequestAccess() automatically shows the system dialog if not granted.
        // Returns true if granted, false otherwise.
        AppLogger.shared.log(
            "🔐 [PermissionRequest] Requesting Input Monitoring via IOHIDRequestAccess()")
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if granted {
            AppLogger.shared.log("✅ [PermissionRequest] Input Monitoring already granted")
        } else {
            AppLogger.shared.log("⏳ [PermissionRequest] Input Monitoring prompt likely shown")
        }
        return granted
    }

    /// Request Accessibility permission using AXIsProcessTrustedWithOptions().
    /// - Returns: true if already granted (no prompt shown), false otherwise.
    @discardableResult
    func requestAccessibilityPermission(ignoreCooldown: Bool = false) -> Bool {
        // Foreground and cooldown guards
        ensureForeground()
        if !isForeground() {
            AppLogger.shared.warn("⚠️ [PermissionRequest] Skipping AX prompt - app not foreground")
            return false
        }
        if !ignoreCooldown, withinCooldown(lastPromptAXKey) {
            AppLogger.shared.info("ℹ️ [PermissionRequest] Skipping AX prompt - within cooldown")
            return false
        }
        markPrompt(lastPromptAXKey)

        // Use the official CFString constant; do not substitute with a plain string
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as CFString
        let options = [key as String: true] as CFDictionary
        AppLogger.shared.log(
            "🔐 [PermissionRequest] Requesting Accessibility via AXIsProcessTrustedWithOptions()")
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            AppLogger.shared.log("✅ [PermissionRequest] Accessibility already granted")
        } else {
            AppLogger.shared.log("⏳ [PermissionRequest] Accessibility prompt likely shown")
        }
        return trusted
    }

    /// Request both permissions (convenience for wizard flows).
    func requestAllPermissions() async -> (inputMonitoring: Bool, accessibility: Bool) {
        let im = requestInputMonitoringPermission()
        try? await Task.sleep(nanoseconds: 500_000_000) // small delay
        let ax = requestAccessibilityPermission()
        return (im, ax)
    }
}

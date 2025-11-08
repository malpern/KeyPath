import ApplicationServices
import Foundation
import IOKit.hid
import AppKit

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
    func requestInputMonitoringPermission() -> Bool {
        // Foreground and cooldown guards
        if !isForeground() || withinCooldown(lastPromptIMKey) {
            return false
        }
        markPrompt(lastPromptIMKey)

        // IOHIDRequestAccess() automatically shows the system dialog if not granted.
        // Returns true if granted, false otherwise.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        return granted
    }

    /// Request Accessibility permission using AXIsProcessTrustedWithOptions().
    /// - Returns: true if already granted (no prompt shown), false otherwise.
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        // Foreground and cooldown guards
        if !isForeground() || withinCooldown(lastPromptAXKey) {
            return false
        }
        markPrompt(lastPromptAXKey)

        let key = "kAXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
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

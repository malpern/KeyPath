import AppKit
@preconcurrency import ApplicationServices // @preconcurrency: ApplicationServices lacks Sendable annotations in Apple SDK
import Foundation
import KeyPathCore
import KeyPathPermissions

/// Centralized utilities for requesting system permissions using Apple's standard APIs.
/// - Requests are debounced to avoid nagging the user.
/// - Requests are only attempted when the app is foreground to ensure the prompt is visible.
@MainActor
public final class PermissionRequestService {
    static let shared = PermissionRequestService()

    private init() {}

    // MARK: - Startup guard

    /// Reference-counted depth tracking for wizard context. Permission requests are only
    /// allowed when depth > 0. Multiple callers (WizardWindowController, the SettingsView
    /// sheet) can push/pop without clobbering each other.
    private var _contextDepth = 0

    /// True when at least one caller has entered a wizard/permission context.
    /// Permission requests are silently suppressed when false to prevent
    /// unexpected system dialogs at launch. See issue #248.
    ///
    /// Note: When suppressed, request methods return `false`, which means both
    /// "permission not granted" and "request was blocked". Most callers use
    /// `@discardableResult` so this is acceptable.
    public var wizardContextActive: Bool {
        _contextDepth > 0
    }

    /// Increment the context depth. Call this when entering a wizard or user-initiated
    /// permission flow. Pair with `leaveWizardContext()`.
    public func enterWizardContext() {
        _contextDepth += 1
        AppLogger.shared.log("🔐 [PermissionRequest] enterWizardContext (depth: \(_contextDepth))")
    }

    /// Decrement the context depth. Call this when leaving a wizard or permission flow.
    public func leaveWizardContext() {
        _contextDepth = max(0, _contextDepth - 1)
        AppLogger.shared.log("🔐 [PermissionRequest] leaveWizardContext (depth: \(_contextDepth))")
    }

    // MARK: - Debounce (cooldown) configuration

    private let cooldownSeconds: TimeInterval = 20 * 60 // 20 minutes
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

    /// Request Accessibility permission using AXIsProcessTrustedWithOptions().
    /// Permission state reads come from PermissionOracle; AXIsProcessTrustedWithOptions is only used to prompt.
    /// - Returns: true if the Oracle reports granted before or immediately after the prompt.
    @discardableResult
    public func requestAccessibilityPermission(ignoreCooldown: Bool = false) async -> Bool {
        // Wizard context guard: block prompts outside wizard/user-initiated flows
        guard wizardContextActive else {
            AppLogger.shared.warn("⚠️ [PermissionRequest] Blocked AX prompt — not in wizard context")
            return false
        }

        let beforePrompt = await SystemStateProvider.shared.currentPermissionSnapshot()
        if beforePrompt.accessibility.isReady {
            AppLogger.shared.log("✅ [PermissionRequest] Accessibility already granted (Oracle)")
            return true
        }

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
            "🔐 [PermissionRequest] Requesting Accessibility via AXIsProcessTrustedWithOptions()"
        )
        _ = AXIsProcessTrustedWithOptions(options)
        let refreshed = await SystemStateProvider.shared.refreshPermissionSnapshot()
        let trusted = refreshed.accessibility.isReady
        if trusted {
            AppLogger.shared.log("✅ [PermissionRequest] Accessibility granted after Oracle refresh")
        } else {
            AppLogger.shared.log("⏳ [PermissionRequest] Accessibility prompt likely shown")
        }
        return trusted
    }
}

/// Sendable is already required of this type: the wizard protocol it conforms to
/// in WizardProtocolConformances.swift inherits Sendable, so the conformance has
/// been in force all along. Swift 6 requires it to be declared alongside the
/// class rather than in the conformance file, so state it here. This records the
/// existing guarantee where the compiler wants it; it is not a new claim about
/// this type's thread safety.
extension PermissionRequestService: @unchecked Sendable {}

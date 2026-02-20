import Foundation
@testable import KeyPathAppKit
import SwiftUI

// MARK: - Mock Factories for Snapshot Testing

/// Provides pre-built model instances for deterministic screenshot rendering.
/// All factories produce stable data suitable for visual regression tests.
enum MockFactories {
    // MARK: - Launcher Models

    static func launcherMapping(
        key: String = "s",
        target: LauncherTarget = .app(name: "Safari", bundleId: "com.apple.Safari"),
        isEnabled: Bool = true
    ) -> LauncherMapping {
        LauncherMapping(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(key.hashValue % 10)")
                ?? UUID(),
            key: key,
            target: target,
            isEnabled: isEnabled
        )
    }

    static func launcherGridConfig(
        mappings: [LauncherMapping]? = nil
    ) -> LauncherGridConfig {
        LauncherGridConfig(
            activationMode: .holdHyper,
            hyperTriggerMode: .hold,
            mappings: mappings ?? defaultLauncherMappings,
            hasSeenWelcome: true
        )
    }

    static var defaultLauncherMappings: [LauncherMapping] {
        [
            launcherMapping(key: "s", target: .app(name: "Safari", bundleId: "com.apple.Safari")),
            launcherMapping(key: "t", target: .app(name: "Terminal", bundleId: "com.apple.Terminal")),
            launcherMapping(key: "m", target: .app(name: "Messages", bundleId: "com.apple.MobileSMS")),
            launcherMapping(key: "f", target: .app(name: "Finder", bundleId: "com.apple.finder")),
            launcherMapping(key: "g", target: .url("https://github.com")),
        ]
    }

    static func quickLaunchMapping(
        key: String = "s",
        targetType: QuickLaunchMapping.TargetType = .app,
        targetName: String = "Safari",
        bundleId: String? = "com.apple.Safari"
    ) -> QuickLaunchMapping {
        QuickLaunchMapping(
            key: key,
            targetType: targetType,
            targetName: targetName,
            bundleId: bundleId
        )
    }

    // MARK: - Rule Models

    static func appKeyOverride(
        inputKey: String = "h",
        outputAction: String = "left_arrow",
        description: String? = nil
    ) -> AppKeyOverride {
        AppKeyOverride(
            inputKey: inputKey,
            outputAction: outputAction,
            description: description
        )
    }

    static func appKeymap(
        bundleIdentifier: String = "com.apple.Safari",
        displayName: String = "Safari",
        overrides: [AppKeyOverride]? = nil
    ) -> AppKeymap {
        AppKeymap(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            overrides: overrides ?? [
                appKeyOverride(inputKey: "h", outputAction: "left_arrow"),
                appKeyOverride(inputKey: "j", outputAction: "down_arrow"),
                appKeyOverride(inputKey: "k", outputAction: "up_arrow"),
                appKeyOverride(inputKey: "l", outputAction: "right_arrow"),
            ]
        )
    }

    static var safariKeymap: AppKeymap {
        appKeymap()
    }

    static var terminalKeymap: AppKeymap {
        appKeymap(
            bundleIdentifier: "com.apple.Terminal",
            displayName: "Terminal",
            overrides: [
                appKeyOverride(inputKey: "n", outputAction: "cmd+t", description: "New tab"),
            ]
        )
    }

    // MARK: - Custom Rules

    static func customRule(
        input: String = "caps_lock",
        output: String = "escape",
        title: String = "",
        isEnabled: Bool = true
    ) -> CustomRule {
        CustomRule(
            title: title,
            input: input,
            output: output,
            isEnabled: isEnabled
        )
    }

    static var sampleGlobalRules: [CustomRule] {
        [
            customRule(input: "caps_lock", output: "escape"),
            customRule(input: "a", output: "left_shift", title: "Home row mod"),
            customRule(input: "f", output: "left_command", title: "Home row mod"),
        ]
    }

    // MARK: - Inspector Panel

    @MainActor
    static func inspectorPanel(
        selectedSection: InspectorSection = .customRules,
        isSettingsShelfActive: Bool = false,
        hasCustomRules: Bool = true,
        customRules: [CustomRule]? = nil,
        appKeymaps: [AppKeymap]? = nil
    ) -> OverlayInspectorPanel {
        OverlayInspectorPanel(
            selectedSection: selectedSection,
            onSelectSection: { _ in },
            fadeAmount: 0,
            isMapperAvailable: true,
            kanataViewModel: nil,
            inspectorReveal: 1.0,
            inspectorTotalWidth: 450,
            inspectorLeadingGap: 0,
            healthIndicatorState: .healthy,
            onHealthTap: {},
            isSettingsShelfActive: isSettingsShelfActive,
            onToggleSettingsShelf: {},
            hasCustomRules: hasCustomRules,
            customRules: customRules ?? sampleGlobalRules,
            appKeymaps: appKeymaps ?? [safariKeymap, terminalKeymap]
        )
    }

    // MARK: - LiveKeyboardOverlay

    @MainActor
    static func keyboardVisualizationViewModel() -> KeyboardVisualizationViewModel {
        let vm = KeyboardVisualizationViewModel()
        vm.layout = .macBookUS
        vm.currentLayerName = "base"
        vm.fadeAmount = 0
        return vm
    }

    @MainActor
    static func overlayUIState(
        isInspectorOpen: Bool = false,
        healthState: HealthIndicatorState = .dismissed
    ) -> LiveKeyboardOverlayUIState {
        let state = LiveKeyboardOverlayUIState()
        state.isInspectorOpen = isInspectorOpen
        state.inspectorReveal = isInspectorOpen ? 1.0 : 0
        state.healthIndicatorState = healthState
        return state
    }

    // MARK: - Home Row Mods

    static func homeRowModsConfig(
        showAdvanced: Bool = false,
        showPerFinger: Bool = false
    ) -> HomeRowModsConfig {
        var config = HomeRowModsConfig()
        config.showAdvanced = showAdvanced
        config.showExpertTiming = showPerFinger
        return config
    }

    // MARK: - Overlay Header

    static func overlayDragHeaderParams(
        isKanataConnected: Bool = true,
        healthState: HealthIndicatorState = .healthy,
        currentLayerName: String = "base",
        isInspectorOpen: Bool = false
    ) -> OverlayDragHeaderParams {
        OverlayDragHeaderParams(
            isDark: false,
            fadeAmount: 0,
            height: 32,
            inspectorWidth: 0,
            reduceTransparency: false,
            isInspectorOpen: isInspectorOpen,
            inputModeIndicator: nil,
            currentLayerName: currentLayerName,
            isLauncherMode: false,
            isKanataConnected: isKanataConnected,
            healthIndicatorState: healthState,
            drawerButtonHighlighted: false
        )
    }
}

/// Groups OverlayDragHeader init params for convenience.
/// Use with `OverlayDragHeader(params:)` or expand inline.
struct OverlayDragHeaderParams {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let inspectorWidth: CGFloat
    let reduceTransparency: Bool
    let isInspectorOpen: Bool
    let inputModeIndicator: String?
    let currentLayerName: String
    let isLauncherMode: Bool
    let isKanataConnected: Bool
    let healthIndicatorState: HealthIndicatorState
    let drawerButtonHighlighted: Bool
}

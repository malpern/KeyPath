import AppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

// MARK: - Layer Display & Hold Label Resolution

extension ContextHUDController {
    func showForLayer(_ layerName: String) {
        if let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           PreferencesService.shared.overlaySuppressedBundleIDs.contains(frontBundle)
        {
            dismiss()
            return
        }
        dismissTask?.cancel()
        dismissTask = nil

        layerMapTask?.cancel()

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                let enabledCollections = await loadEnabledCollections()

                let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
                let layout = PhysicalLayout.find(id: layoutId) ?? .macBookUS

                let normalizedLayerName = layerName.lowercased()
                let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let isApprovedNeovimTerminal = NeovimTerminalScope.isApprovedTerminal(
                    bundleIdentifier: frontmostBundleIdentifier
                )
                let scopedEnabledCollections = isApprovedNeovimTerminal
                    ? enabledCollections
                    : enabledCollections.filter { $0.id != RuleCollectionIdentifier.neovimTerminal }

                let collectionLauncherKeyMap = buildLauncherKeyMap(from: scopedEnabledCollections)

                let keyMap: [UInt16: LayerKeyInfo]
                let launcherKeyMap: [UInt16: LayerKeyInfo]? = nil

                if normalizedLayerName == "launcher" {
                    keyMap = collectionLauncherKeyMap
                    await preloadLauncherIcons(keyMap: keyMap)
                } else {
                    keyMap = try await layerKeyMapper.getMapping(
                        for: layerName,
                        configPath: configPath,
                        layout: layout,
                        collections: scopedEnabledCollections,
                        cacheKeySuffix: "neovim-scope-\(isApprovedNeovimTerminal ? "approved" : "fallback")"
                    ).mapping
                }

                guard !Task.isCancelled else { return }

                var effectiveKeyMap = keyMap
                let hasRawNeovimEntries = keyMap.values.contains {
                    $0.collectionId == RuleCollectionIdentifier.neovimTerminal
                }
                if hasRawNeovimEntries, !isApprovedNeovimTerminal {
                    effectiveKeyMap = keyMap.filter { _, info in
                        info.collectionId != RuleCollectionIdentifier.neovimTerminal
                    }
                }

                guard !Task.isCancelled else { return }

                let hasRenderableEntries = effectiveKeyMap.values.contains { info in
                    !info.isTransparent && !info.isLayerSwitch
                }

                if effectiveKeyMap.isEmpty || !hasRenderableEntries {
                    if hasRawNeovimEntries, !isApprovedNeovimTerminal {
                        AppLogger.shared.info(
                            "🎯 [ContextHUD] Suppressing Neovim HUD outside approved terminals (frontmost=\(frontmostBundleIdentifier ?? "nil"))"
                        )
                    }
                    dismiss()
                    return
                }

                let resolvedStyle = HUDContentResolver.resolve(
                    layerName: layerName,
                    keyMap: effectiveKeyMap,
                    collections: scopedEnabledCollections
                )

                let hasNeovimEntries = effectiveKeyMap.values.contains { $0.collectionId == RuleCollectionIdentifier.neovimTerminal }
                let shouldUseNeovimStyle = normalizedLayerName == "nav" &&
                    hasNeovimEntries &&
                    isApprovedNeovimTerminal

                let style: HUDContentStyle = if shouldUseNeovimStyle {
                    .neovimTerminal
                } else {
                    resolvedStyle
                }

                guard !Task.isCancelled else { return }

                var holdLabels = holdLabelCache[normalizedLayerName] ?? [:]

                if holdLabels.isEmpty {
                    holdLabels = await resolveHoldLabels(
                        keyMap: effectiveKeyMap,
                        configPath: configPath,
                        layerName: layerName
                    )
                    guard !Task.isCancelled else { return }
                    if !holdLabels.isEmpty {
                        holdLabelCache[normalizedLayerName] = holdLabels
                    }
                }

                guard !Task.isCancelled else { return }

                viewModel.update(
                    layerName: layerName,
                    keyMap: effectiveKeyMap,
                    collections: scopedEnabledCollections,
                    style: style,
                    holdLabels: holdLabels,
                    launcherKeyMap: launcherKeyMap,
                    kindaVimState: nil,
                    kindaVimLeaderHUDMode: .off
                )

                showWindow()
            } catch {
                AppLogger.shared.error("🎯 [ContextHUD] Failed to build layer mapping: \(error)")
            }
        }
    }

    func resolveHoldLabels(
        keyMap: [UInt16: LayerKeyInfo],
        configPath: String,
        layerName: String
    ) async -> [UInt16: String] {
        let candidates = keyMap.filter { _, info in
            !info.isTransparent && !info.isLayerSwitch
        }
        guard !candidates.isEmpty else { return [:] }

        var result: [UInt16: String] = [:]
        await withTaskGroup(of: (UInt16, String?).self) { group in
            for (keyCode, info) in candidates {
                group.addTask { [layerKeyMapper] in
                    do {
                        let label = try await layerKeyMapper.holdDisplayLabel(
                            for: keyCode,
                            configPath: configPath,
                            startLayer: layerName
                        )
                        if let label, label != info.displayLabel {
                            return (keyCode, label)
                        }
                        return (keyCode, nil)
                    } catch {
                        return (keyCode, nil)
                    }
                }
            }
            for await (keyCode, label) in group {
                if let label {
                    result[keyCode] = label
                }
            }
        }
        return result
    }

    func precomputeNavLayer(debounce: Bool = false) {
        precomputeTask?.cancel()
        precomputeTask = Task { [weak self] in
            guard let self else { return }
            if debounce {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            }

            AppLogger.shared.info("🎯 [ContextHUD] Background precompute starting")

            let configPath = WizardSystemPaths.userConfigPath
            let enabledCollections = await loadEnabledCollections()
            let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
            let layout = PhysicalLayout.find(id: layoutId) ?? .macBookUS

            for layerName in Self.precomputeLayers {
                guard !Task.isCancelled else { return }

                do {
                    if layerName == "launcher" {
                        let keyMap = buildLauncherKeyMap(from: enabledCollections)
                        await preloadLauncherIcons(keyMap: keyMap)
                        AppLogger.shared.info("🎯 [ContextHUD] Precomputed launcher icons")
                    } else {
                        let (keyMap, _) = try await layerKeyMapper.getMapping(
                            for: layerName,
                            configPath: configPath,
                            layout: layout,
                            collections: enabledCollections
                        )
                        guard !Task.isCancelled else { return }

                        let holdLabels = await resolveHoldLabels(
                            keyMap: keyMap,
                            configPath: configPath,
                            layerName: layerName
                        )
                        guard !Task.isCancelled else { return }
                        if !holdLabels.isEmpty {
                            holdLabelCache[layerName] = holdLabels
                        }
                        AppLogger.shared.info("🎯 [ContextHUD] Precomputed layer '\(layerName)'")
                    }
                } catch {
                    AppLogger.shared.debug("🎯 [ContextHUD] Precompute failed for '\(layerName)': \(error)")
                }
            }

            AppLogger.shared.info("🎯 [ContextHUD] Background precompute complete")
        }
    }
}

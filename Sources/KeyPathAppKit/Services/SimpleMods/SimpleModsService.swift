import Foundation
import KeyPathCore
import Observation

/// Main service for managing simple modifications
@MainActor
@Observable
public final class SimpleModsService {
    public private(set) var installedMappings: [SimpleMapping] = []
    public private(set) var availablePresets: [SimpleModPreset] = []
    public private(set) var conflicts: [MappingConflict] = []
    public private(set) var isApplying = false
    public private(set) var lastError: String?
    public private(set) var lastRollbackReason: String? // Tracks why a rollback occurred
    public private(set) var lastRollbackDetails: String? // Additional diagnostic details

    @ObservationIgnored private let configPath: String
    @ObservationIgnored private let parser: SimpleModsParser
    @ObservationIgnored private let writer: SimpleModsWriter
    @ObservationIgnored private let catalog = SimpleModsCatalog.shared

    // Debounce timer for instant apply
    @ObservationIgnored private var applyDebounceTask: Task<Void, Never>?
    @ObservationIgnored private let debounceDelay: TimeInterval = 0.3

    typealias EditTransform = @MainActor @Sendable (String) throws -> String
    typealias ApplyEdit = @MainActor (@escaping EditTransform) async -> SaveResult
    @ObservationIgnored private var applyEdit: ApplyEdit?
    @ObservationIgnored private var loadedContent: String?
    @ObservationIgnored private var editRevision = 0
    private(set) var lastSaveResult: SaveResult?

    public init(configPath: String) {
        self.configPath = configPath
        parser = SimpleModsParser(configPath: configPath)
        writer = SimpleModsWriter(configPath: configPath)
    }

    convenience init(configPath: String, applyEdit: @escaping ApplyEdit) {
        self.init(configPath: configPath)
        self.applyEdit = applyEdit
    }

    /// Connect the editor to the existing runtime save owner.
    func setDependencies(kanataManager: RuntimeCoordinator?) {
        let path = configPath
        applyEdit = { [weak kanataManager] transform in
            guard let kanataManager else {
                return .failure(KeyPathError.configuration(.loadFailed(reason: "Configuration service unavailable")))
            }
            return await kanataManager.editConfiguration(at: path, transform: transform)
        }
    }

    /// Load current mappings from config
    public func load() throws {
        AppLogger.shared.log("📖 [SimpleMods] Loading mappings from config: \(configPath)")
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        let (_, allMappings, detectedConflicts) = try parser.parse(content: content)
        loadedContent = content
        conflicts = detectedConflicts

        AppLogger.shared.log("📖 [SimpleMods] Found \(allMappings.count) installed mapping(s)")
        if !detectedConflicts.isEmpty {
            AppLogger.shared.log("⚠️ [SimpleMods] Detected \(detectedConflicts.count) conflict(s)")
        }

        // Installed mappings are those that exist in the config file
        installedMappings = allMappings

        // Available presets are those NOT in the config file
        let installedKeys = Set(allMappings.map { "\($0.fromKey)->\($0.toKey)" })
        let allPresets = catalog.getAllPresets()
        availablePresets = allPresets.filter { preset in
            !installedKeys.contains("\(preset.fromKey)->\(preset.toKey)")
        }

        AppLogger.shared.log(
            "📖 [SimpleMods] Load complete: \(installedMappings.count) installed, \(availablePresets.count) available"
        )
        lastError = nil
        lastRollbackReason = nil
        lastRollbackDetails = nil
    }

    /// Add a preset to the config (installed mappings)
    public func addMapping(fromKey: String, toKey: String, enabled: Bool = true) {
        AppLogger.shared.log("➕ [SimpleMods] Add mapping: \(fromKey) → \(toKey) (enabled=\(enabled))")
        // Check if already installed
        if installedMappings.contains(where: { $0.fromKey == fromKey && $0.toKey == toKey }) {
            lastError = "Mapping already installed"
            return
        }

        let newMapping = SimpleMapping(
            fromKey: fromKey,
            toKey: toKey,
            enabled: enabled,
            filePath: configPath
        )

        installedMappings.append(newMapping)

        // Remove from available presets
        availablePresets.removeAll { $0.fromKey == fromKey && $0.toKey == toKey }

        // Apply changes
        scheduleApply()
    }

    /// Remove a mapping from the config entirely
    public func removeMapping(id: UUID) {
        guard let index = installedMappings.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = installedMappings.remove(at: index)
        AppLogger.shared.log("🗑️ [SimpleMods] Remove mapping: \(removed.fromKey) → \(removed.toKey)")

        // Add back to available presets if it's a prese
        if let preset = catalog.findPreset(fromKey: removed.fromKey, toKey: removed.toKey) {
            availablePresets.append(preset)
        }

        // Apply changes
        scheduleApply()
    }

    /// Toggle a mapping on/off with instant apply
    public func toggleMapping(id: UUID, enabled: Bool) {
        guard let index = installedMappings.firstIndex(where: { $0.id == id }) else {
            return
        }

        // Optimistic update
        installedMappings[index].enabled = enabled
        AppLogger.shared.log(
            "🔁 [SimpleMods] Toggle mapping: \(installedMappings[index].fromKey) → \(installedMappings[index].toKey) -> \(enabled ? "ON" : "OFF")"
        )
        isApplying = true

        // Debounce apply
        scheduleApply()
    }

    private func scheduleApply() {
        editRevision += 1
        isApplying = true
        let previous = applyDebounceTask
        previous?.cancel()
        applyDebounceTask = Task {
            try? await Task.sleep(for: .seconds(debounceDelay))
            // Cancelled queued edits still preserve the settlement chain.
            await previous?.value
            guard !Task.isCancelled else { return }
            await applyChanges()
        }
    }

    #if DEBUG
        func flushPendingApplyForTesting() async {
            let previous = applyDebounceTask
            previous?.cancel()
            let task = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                await applyChanges()
            }
            applyDebounceTask = task
            await task.value
        }
    #endif

    private func applyChanges() async {
        guard !Task.isCancelled else { return }
        let revision = editRevision
        let desiredMappings = installedMappings
        let expectedContent = loadedContent
        var renderedContent: String?
        let writer = writer
        let result: SaveResult = if let applyEdit, let expectedContent {
            await applyEdit { content in
                guard content == expectedContent else {
                    throw KeyPathError.configuration(.loadFailed(reason: "The configuration changed outside this editor. Reload mappings before trying again."))
                }
                let rendered = try writer.renderBlock(mappings: desiredMappings, in: content)
                renderedContent = rendered
                return rendered
            }
        } else {
            .failure(KeyPathError.configuration(.loadFailed(reason: "Load the configuration and connect its save service before editing mappings.")))
        }
        if result.success { loadedContent = renderedContent }
        // A newer edit owns the optimistic list and status until it is saved.
        guard revision == editRevision else { return }
        isApplying = false
        lastSaveResult = result
        if result.success {
            do { try load() }
            catch { lastError = "Saved, but the configuration could not be refreshed: \(error.localizedDescription)" }
        } else {
            try? load()
            lastRollbackReason = nil
            lastRollbackDetails = nil
            let cause = result.error?.localizedDescription ?? "The mappings could not be saved."
            switch result.recoveryResult {
            case .restoredPreviousConfig:
                lastRollbackReason = cause
                lastRollbackDetails = "The previous configuration file was restored. Runtime recovery has not been verified."
                lastError = cause
            case let .wroteMinimalSafeConfig(backupError):
                lastError = "\(cause) The previous configuration could not be restored; a minimal safe file was written. \(backupError?.localizedDescription ?? "")"
            case let .failed(backupError, fallbackError):
                lastError = "\(cause) Configuration recovery failed: \(backupError?.localizedDescription ?? "") \(fallbackError.localizedDescription)"
            case .notAttempted:
                lastError = cause
            case .restoredPreviousAppKeymapState, .appKeymapRecoveryFailed, .restoredPreviousRuleState, .ruleStateRecoveryFailed:
                // This editor uses raw-file saves, not the app-keymap transaction.
                lastError = cause
            }
        }
    }

    /// Get presets by category
    public func getPresetsByCategory() -> [String: [SimpleModPreset]] {
        catalog.getPresetsByCategory()
    }
}

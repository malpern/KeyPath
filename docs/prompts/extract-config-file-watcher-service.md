# Task: Extract ConfigFileWatcherService from RuntimeCoordinator

## Objective
Extract the configuration file watching and hot-reload logic from `RuntimeCoordinator.swift` into a dedicated `ConfigFileWatcherService.swift` service.

## Why This Extraction?
RuntimeCoordinator (2,321 lines) contains config file watching logic that:
- Watches for external file changes
- Validates changed configs
- Triggers hot reload via TCP
- Updates in-memory state
- Plays sound feedback

This is a self-contained concern that should be a separate service.

## Source Location
`Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift`

Look for the `// MARK: - Configuration File Watching` section (around lines 610-740).

## Target File
Create: `Sources/KeyPathAppKit/Services/ConfigFileWatcherService.swift`

## Code to Extract

1. **startConfigFileWatching()** - Start watching config file
2. **stopConfigFileWatching()** - Stop watching
3. **handleExternalConfigChange()** - Handle detected changes
4. **updateInMemoryConfig()** - Parse and update in-memory state

## Service Structure

```swift
import Foundation
import KeyPathCore

/// Watches configuration file for external changes and triggers hot reload.
///
/// This service monitors the keypath.kbd config file and:
/// - Detects external edits (from text editors, etc.)
/// - Validates changed configuration via CLI
/// - Triggers hot reload via TCP to running Kanata
/// - Provides callback for UI updates (sound, status)
final class ConfigFileWatcherService {
    static let shared = ConfigFileWatcherService()
    
    private var configFileWatcher: ConfigFileWatcher?
    private var configurationService: ConfigurationService?
    
    /// Callback for external change events
    var onExternalChange: ((ExternalChangeResult) -> Void)?
    
    struct ExternalChangeResult {
        let success: Bool
        let message: String
        let newContent: String?
    }
    
    private init() {}
    
    func configure(
        configurationService: ConfigurationService,
        reloadHandler: @escaping () async -> Bool
    ) {
        // Store dependencies
    }
    
    func startWatching(configPath: String) {
        // Implementation from RuntimeCoordinator
    }
    
    func stopWatching() {
        // Implementation from RuntimeCoordinator
    }
    
    private func handleExternalChange(configPath: String) async {
        // Implementation from RuntimeCoordinator.handleExternalConfigChange()
    }
}
```

## Integration Pattern

After extraction, RuntimeCoordinator should delegate:

```swift
// In RuntimeCoordinator.init():
configFileWatcherService = ConfigFileWatcherService.shared
configFileWatcherService.configure(
    configurationService: configurationService,
    reloadHandler: { [weak self] in
        await self?.triggerConfigReload().isSuccess ?? false
    }
)
configFileWatcherService.onExternalChange = { [weak self] result in
    Task { @MainActor in
        if result.success {
            SoundManager.shared.playGlassSound()
            self?.saveStatus = .success
        } else {
            SoundManager.shared.playErrorSound()
            self?.saveStatus = .failed(result.message)
        }
    }
}

// Replace direct calls:
func startConfigFileWatching() {
    configFileWatcherService.startWatching(configPath: configPath)
}

func stopConfigFileWatching() {
    configFileWatcherService.stopWatching()
}
```

## Git Workflow

```bash
git checkout master
git pull
git checkout -b refactor/extract-config-file-watcher-service
# Make changes
swift build
swift test
git add -A
git commit -m "refactor: extract ConfigFileWatcherService from RuntimeCoordinator"
git push -u origin refactor/extract-config-file-watcher-service
```

## Validation

1. `swift build` passes
2. `swift test` passes (60 tests)
3. Config file watching still works (external edits trigger reload)

## Estimated Size
~150 lines of clean, focused code


import AppKit
import Foundation

/// Service for monitoring configuration file changes and triggering hot reloads
class ConfigFileWatcher: ObservableObject {
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?
    private var debounceTimer: Timer?
    private var watchedFilePath: String?
    private var isWatching = false

    private let debounceDelay: TimeInterval = 0.5 // 500ms debounce

    // Callback for when file changes are detected
    private var onFileChanged: (() async -> Void)?

    init() {
        AppLogger.shared.log("📁 [FileWatcher] ConfigFileWatcher initialized")
    }

    deinit {
        stopWatching()
        AppLogger.shared.log("📁 [FileWatcher] ConfigFileWatcher deinitialized")
    }

    /// Start watching a file for changes
    /// - Parameters:
    ///   - path: The file path to monitor
    ///   - onChange: Callback to execute when file changes are detected
    func startWatching(path: String, onChange: @escaping () async -> Void) {
        guard !isWatching else {
            AppLogger.shared.log("⚠️ [FileWatcher] Already watching file - stopping previous watch")
            stopWatching()
            return
        }

        watchedFilePath = path
        onFileChanged = onChange

        // Get initial modification date
        updateLastModificationDate()

        // Create file descriptor for monitoring
        guard let fileDescriptor = openFileDescriptor(at: path) else {
            AppLogger.shared.log("❌ [FileWatcher] Failed to open file descriptor for: \(path)")
            return
        }

        // Create dispatch source for file system monitoring
        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        // Set up event handler
        fileMonitorSource?.setEventHandler { [weak self] in
            Task {
                await self?.handleFileChangeEvent()
            }
        }

        // Set up cancellation handler to close file descriptor
        fileMonitorSource?.setCancelHandler {
            close(fileDescriptor)
        }

        // Start monitoring
        fileMonitorSource?.resume()
        isWatching = true

        AppLogger.shared.log("📁 [FileWatcher] Started watching: \(path)")
    }

    /// Stop watching the current file
    func stopWatching() {
        guard isWatching else { return }

        debounceTimer?.invalidate()
        debounceTimer = nil

        fileMonitorSource?.cancel()
        fileMonitorSource = nil

        isWatching = false
        watchedFilePath = nil
        onFileChanged = nil
        lastModificationDate = nil

        AppLogger.shared.log("📁 [FileWatcher] Stopped watching file")
    }

    /// Check if currently watching a file
    var isActive: Bool {
        return isWatching
    }

    // MARK: - Private Methods

    private func openFileDescriptor(at path: String) -> Int32? {
        let fd = open(path, O_EVTONLY)
        return fd >= 0 ? fd : nil
    }

    private func updateLastModificationDate() {
        guard let path = watchedFilePath else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            lastModificationDate = attributes[.modificationDate] as? Date
        } catch {
            AppLogger.shared.log("⚠️ [FileWatcher] Failed to get modification date: \(error)")
            lastModificationDate = nil
        }
    }

    private func hasFileActuallyChanged() -> Bool {
        guard let path = watchedFilePath else { return false }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let currentModDate = attributes[.modificationDate] as? Date

            // If we don't have a previous date, consider it changed
            guard let lastDate = lastModificationDate else { return true }

            // Check if modification date has actually changed
            let hasChanged = currentModDate != lastDate

            if hasChanged {
                lastModificationDate = currentModDate
                AppLogger.shared.log("📁 [FileWatcher] File modification detected at \(currentModDate?.description ?? "unknown")")
            }

            return hasChanged
        } catch {
            AppLogger.shared.log("⚠️ [FileWatcher] Error checking file modification: \(error)")
            return false
        }
    }

    private func handleFileChangeEvent() async {
        guard isWatching else { return }

        AppLogger.shared.log("📁 [FileWatcher] File change event received")

        // Cancel any existing debounce timer
        debounceTimer?.invalidate()

        // Set up debounce timer to handle rapid file changes
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task {
                await self?.processFileChange()
            }
        }
    }

    private func processFileChange() async {
        guard let path = watchedFilePath else { return }

        AppLogger.shared.log("📁 [FileWatcher] Processing debounced file change for: \(path)")

        // Check if file actually changed (avoid false positives)
        guard hasFileActuallyChanged() else {
            AppLogger.shared.log("📁 [FileWatcher] File modification date unchanged - skipping")
            return
        }

        // Check if file still exists
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.shared.log("⚠️ [FileWatcher] Watched file no longer exists: \(path)")
            return
        }

        AppLogger.shared.log("📁 [FileWatcher] Triggering file change callback")

        // Trigger the callback
        await onFileChanged?()
    }
}

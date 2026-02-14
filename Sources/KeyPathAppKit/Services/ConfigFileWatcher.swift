import AppKit
import Foundation
import KeyPathCore
import Observation

/// Service for monitoring configuration file changes and triggering hot reloads
///
/// This implementation uses best practices for file system monitoring:
/// - Watches parent directory when target file doesn't exist
/// - Handles atomic writes by monitoring file creation/deletion/move events
/// - Provides comprehensive error logging and recovery
/// - Uses proper file descriptor management with cleanup
///
/// All mutable state is isolated to `@MainActor` since this is an `@Observable` class
/// owned by `@MainActor`-isolated coordinators.
@MainActor
@Observable
class ConfigFileWatcher {
    // MARK: - Properties

    @ObservationIgnored private var fileMonitorSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var directoryMonitorSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var lastModificationDate: Date?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var watchedFilePath: String?
    @ObservationIgnored private var watchedDirectoryPath: String?
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var isWatchingDirectory = false

    @ObservationIgnored private let debounceDelay: TimeInterval = 0.5 // 500ms debounce
    @ObservationIgnored private let maxRetries = 3
    @ObservationIgnored private var retryCount = 0
    @ObservationIgnored private var pendingAtomicWriteEvent = false

    // Suppression to prevent self-initiated reload loops
    @ObservationIgnored private var suppressUntil: Date?
    @ObservationIgnored private var inFlightProcessing = false

    /// Dedicated queue for file system events (avoid main thread contention)
    /// The DispatchSource fires events on this queue, but handlers immediately
    /// hop to MainActor via Task { @MainActor in ... }
    @ObservationIgnored private let queue = DispatchQueue(label: "com.keypath.configwatcher", qos: .utility)

    /// Callback for when file changes are detected
    @ObservationIgnored private var onFileChanged: (@MainActor () async -> Void)?

    init() {
        AppLogger.shared.log("📁 [FileWatcher] ConfigFileWatcher initialized with robust monitoring")
    }

    deinit {
        // deinit cannot be @MainActor, so we capture what we need and clean up directly.
        // DispatchSource.cancel() is thread-safe and can be called from any thread.
        fileMonitorSource?.cancel()
        directoryMonitorSource?.cancel()
        debounceTask?.cancel()
        AppLogger.shared.log("📁 [FileWatcher] ConfigFileWatcher deinitialized")
    }

    // MARK: - Suppression API

    /// Suppress file watcher events for a duration to prevent self-initiated reload loops
    func suppressEvents(for duration: TimeInterval, reason: String? = nil) {
        suppressUntil = Date().addingTimeInterval(duration)
        let reasonText = reason ?? "unspecified"
        AppLogger.shared.log("🔇 [FileWatcher] Suppressing events for \(duration)s - \(reasonText)")
    }

    private func isSuppressedNow() -> Bool {
        if let until = suppressUntil, Date() < until {
            return true
        }
        return false
    }

    /// Start watching a file for changes
    /// - Parameters:
    ///   - path: The file path to monitor
    ///   - onChange: Callback to execute when file changes are detected
    func startWatching(path: String, onChange: @MainActor @escaping () async -> Void) {
        if isWatching || isWatchingDirectory {
            AppLogger.shared.log(
                "⚠️ [FileWatcher] Already watching - stopping previous watch before starting new one"
            )
            stopWatching()
        }

        watchedFilePath = path
        watchedDirectoryPath = (path as NSString).deletingLastPathComponent
        onFileChanged = onChange
        retryCount = 0

        AppLogger.shared.log("📁 [FileWatcher] Starting to watch file: \(path)")
        AppLogger.shared.log("📁 [FileWatcher] Parent directory: \(watchedDirectoryPath ?? "unknown")")

        // Check if file exists and start appropriate monitoring
        if FileManager.default.fileExists(atPath: path) {
            AppLogger.shared.log("📁 [FileWatcher] Target file exists - setting up direct file monitoring")
            setupFileMonitoring()
        } else {
            AppLogger.shared.log(
                "📁 [FileWatcher] Target file doesn't exist - setting up directory monitoring for file creation"
            )
            setupDirectoryMonitoring()
        }
    }

    // MARK: - File Monitoring Setup

    /// Set up direct file monitoring when the target file exists
    private func setupFileMonitoring() {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("❌ [FileWatcher] No file path set for monitoring")
            return
        }

        // Get initial modification date
        updateLastModificationDate()

        // Create file descriptor for monitoring
        guard let fileDescriptor = openFileDescriptor(at: path) else {
            AppLogger.shared.log("❌ [FileWatcher] Failed to open file descriptor for: \(path)")
            handleFileMonitoringFailure()
            return
        }

        AppLogger.shared.log(
            "📁 [FileWatcher] Successfully opened file descriptor \(fileDescriptor) for: \(path)"
        )

        // Create dispatch source for file system monitoring
        // Monitor write, delete, rename, and attribute changes to handle atomic writes
        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )

        // Set up event handler with atomic write detection
        // The handler fires on `queue` but immediately hops to MainActor.
        // We capture `source` directly so we can read `.data` synchronously
        // in the handler without touching @MainActor-isolated state.
        let source = fileMonitorSource!
        source.setEventHandler { [weak self] in
            guard self != nil else { return }
            let flags = DispatchSource.FileSystemEvent(rawValue: source.data)
            AppLogger.shared.log("📁 [FileWatcher] File system event received - flags: \(flags)")
            Task { @MainActor [weak self] in
                await self?.handleFileEvent(flags: flags)
            }
        }

        // Set up cancellation handler to close file descriptor
        fileMonitorSource?.setCancelHandler {
            AppLogger.shared.log("📁 [FileWatcher] Closing file descriptor \(fileDescriptor)")
            close(fileDescriptor)
        }

        // Start monitoring
        fileMonitorSource?.resume()
        isWatching = true
        retryCount = 0

        AppLogger.shared.log("✅ [FileWatcher] Successfully started file monitoring for: \(path)")
    }

    /// Set up directory monitoring to watch for file creation
    private func setupDirectoryMonitoring() {
        guard let directoryPath = watchedDirectoryPath else {
            AppLogger.shared.log("❌ [FileWatcher] No directory path set for monitoring")
            return
        }

        // Ensure directory exists
        guard FileManager.default.fileExists(atPath: directoryPath) else {
            AppLogger.shared.log("❌ [FileWatcher] Directory doesn't exist: \(directoryPath)")
            handleDirectoryMonitoringFailure()
            return
        }

        // Create directory file descriptor
        guard let dirDescriptor = openFileDescriptor(at: directoryPath) else {
            AppLogger.shared.log(
                "❌ [FileWatcher] Failed to open directory descriptor for: \(directoryPath)"
            )
            handleDirectoryMonitoringFailure()
            return
        }

        AppLogger.shared.log(
            "📁 [FileWatcher] Successfully opened directory descriptor \(dirDescriptor) for: \(directoryPath)"
        )

        // Create dispatch source for directory monitoring
        directoryMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        // Set up event handler for directory changes
        // The handler fires on `queue` but immediately hops to MainActor
        directoryMonitorSource?.setEventHandler {
            AppLogger.shared.log(
                "📁 [FileWatcher] Directory event received - checking if target file was created"
            )
            Task { @MainActor [weak self] in
                await self?.handleDirectoryChangeEvent()
            }
        }

        // Set up cancellation handler
        directoryMonitorSource?.setCancelHandler {
            AppLogger.shared.log("📁 [FileWatcher] Closing directory descriptor \(dirDescriptor)")
            close(dirDescriptor)
        }

        // Start monitoring
        directoryMonitorSource?.resume()
        isWatchingDirectory = true
        retryCount = 0

        AppLogger.shared.log(
            "✅ [FileWatcher] Successfully started directory monitoring for: \(directoryPath)"
        )
    }

    /// Stop watching the current file and directory
    func stopWatching() {
        AppLogger.shared.log("📁 [FileWatcher] Stopping all monitoring...")

        // Stop debounce timer
        debounceTask?.cancel()
        debounceTask = nil

        // Stop file monitoring
        if isWatching {
            AppLogger.shared.log("📁 [FileWatcher] Stopping file monitoring")
            fileMonitorSource?.cancel()
            fileMonitorSource = nil
            isWatching = false
        }

        // Stop directory monitoring
        if isWatchingDirectory {
            AppLogger.shared.log("📁 [FileWatcher] Stopping directory monitoring")
            directoryMonitorSource?.cancel()
            directoryMonitorSource = nil
            isWatchingDirectory = false
        }

        // Reset state
        watchedFilePath = nil
        watchedDirectoryPath = nil
        onFileChanged = nil
        lastModificationDate = nil
        retryCount = 0

        AppLogger.shared.log("✅ [FileWatcher] All monitoring stopped and state cleared")
    }

    /// Check if currently watching a file or directory
    var isActive: Bool {
        isWatching || isWatchingDirectory
    }

    // MARK: - Event Handlers

    /// Handle file system events with atomic write detection and file descriptor rebinding
    private func handleFileEvent(flags: DispatchSource.FileSystemEvent) async {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("⚠️ [FileWatcher] File event but no watched file path")
            return
        }

        // Handle atomic writes by rebinding file descriptor on rename/delete.
        // This MUST happen before the suppression check — if the file was atomically
        // replaced during suppression, the old file descriptor becomes stale and the
        // watcher goes permanently dead.
        if flags.contains(.rename) || flags.contains(.delete) {
            AppLogger.shared.log(
                "📁 [FileWatcher] Detected atomic write (rename/delete) - rebinding file descriptor"
            )
            pendingAtomicWriteEvent = true
            rebindFileMonitor(to: path)
        }

        // Check for suppression — skip the callback but descriptor is already rebound above
        if isSuppressedNow() {
            AppLogger.shared.log("🔇 [FileWatcher] Event suppressed - skipping processing")
            return
        }

        if inFlightProcessing {
            AppLogger.shared.log("📁 [FileWatcher] Event already being processed - skipping duplicate")
            return
        }

        inFlightProcessing = true
        defer { inFlightProcessing = false }

        // Process the change event
        await handleFileChangeEvent()
    }

    /// Rebind file monitor to handle atomic writes where the file descriptor becomes stale
    private func rebindFileMonitor(to path: String) {
        AppLogger.shared.log("🔄 [FileWatcher] Rebinding file monitor to: \(path)")

        // Cancel current file monitor
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        isWatching = false

        // Wait a brief moment for atomic write to complete, then re-setup on MainActor
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50)) // 50ms
            self?.setupFileMonitoring()
        }
    }

    /// Handle directory changes to detect file creation
    private func handleDirectoryChangeEvent() async {
        guard let filePath = watchedFilePath else { return }

        AppLogger.shared.log("📁 [FileWatcher] Processing directory change event")

        // Check if our target file was created
        if FileManager.default.fileExists(atPath: filePath) {
            AppLogger.shared.log("🎉 [FileWatcher] Target file was created! Switching to file monitoring")

            // Stop directory monitoring
            directoryMonitorSource?.cancel()
            directoryMonitorSource = nil
            isWatchingDirectory = false

            // Start file monitoring
            setupFileMonitoring()

            // Trigger initial change callback since the file was just created
            AppLogger.shared.log("📁 [FileWatcher] Triggering change callback for newly created file")
            await onFileChanged?()
        } else {
            AppLogger.shared.log("📁 [FileWatcher] Directory changed but target file not yet created")
        }
    }

    /// Handle file system events with comprehensive logging
    private func handleFileChangeEvent() async {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("⚠️ [FileWatcher] File change event but no watched file path")
            return
        }

        AppLogger.shared.log("📁 [FileWatcher] Processing file change event for: \(path)")

        // Check if file still exists (handles atomic writes where file is deleted/recreated)
        if !FileManager.default.fileExists(atPath: path) {
            AppLogger.shared.log(
                "⚠️ [FileWatcher] File no longer exists - may be atomic write in progress"
            )

            // For atomic writes, the file might be temporarily gone
            // Wait a brief moment and check again
            try? await Task.sleep(for: .milliseconds(100)) // 100ms

            if FileManager.default.fileExists(atPath: path) {
                AppLogger.shared.log("📁 [FileWatcher] File reappeared - atomic write completed")
            } else {
                AppLogger.shared.log(
                    "❌ [FileWatcher] File permanently deleted - switching to directory monitoring"
                )

                // File was deleted, switch to directory monitoring
                fileMonitorSource?.cancel()
                fileMonitorSource = nil
                isWatching = false

                setupDirectoryMonitoring()
                return
            }
        }

        // Cancel any existing debounce task
        debounceTask?.cancel()

        // Schedule debounce task to handle rapid file changes
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(debounceDelay))
            await processFileChange()
        }
    }

    // MARK: - Error Handling

    private func handleFileMonitoringFailure() {
        AppLogger.shared.log("❌ [FileWatcher] File monitoring setup failed")

        if retryCount < maxRetries {
            retryCount += 1
            AppLogger.shared.log(
                "🔄 [FileWatcher] Retrying file monitoring setup (attempt \(retryCount)/\(maxRetries))"
            )

            // Retry after a brief delay on MainActor
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1)) // 1s
                self?.setupFileMonitoring()
            }
        } else {
            AppLogger.shared.log(
                "❌ [FileWatcher] Max retries reached for file monitoring - falling back to directory monitoring"
            )
            setupDirectoryMonitoring()
        }
    }

    private func handleDirectoryMonitoringFailure() {
        AppLogger.shared.log("❌ [FileWatcher] Directory monitoring setup failed")

        if retryCount < maxRetries {
            retryCount += 1
            AppLogger.shared.log(
                "🔄 [FileWatcher] Retrying directory monitoring setup (attempt \(retryCount)/\(maxRetries))"
            )

            // Retry after a brief delay on MainActor
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2)) // 2s
                self?.setupDirectoryMonitoring()
            }
        } else {
            AppLogger.shared.log(
                "❌ [FileWatcher] Max retries reached for directory monitoring - file watching disabled"
            )
        }
    }

    // MARK: - Private Methods

    private nonisolated func openFileDescriptor(at path: String) -> Int32? {
        let fd = open(path, O_EVTONLY)
        if fd >= 0 {
            AppLogger.shared.log("📁 [FileWatcher] Successfully opened file descriptor \(fd) for: \(path)")
            return fd
        } else {
            let error = String(cString: strerror(errno))
            AppLogger.shared.log(
                "❌ [FileWatcher] Failed to open file descriptor for \(path): \(error) (errno: \(errno))"
            )
            return nil
        }
    }

    private func updateLastModificationDate() {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("⚠️ [FileWatcher] Cannot update modification date - no watched file path")
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let modDate = attributes[.modificationDate] as? Date
            lastModificationDate = modDate
            AppLogger.shared.log(
                "📁 [FileWatcher] Updated last modification date: \(modDate?.description ?? "nil")"
            )
        } catch {
            AppLogger.shared.log("⚠️ [FileWatcher] Failed to get modification date for \(path): \(error)")
            lastModificationDate = nil
        }
    }

    private func hasFileActuallyChanged() -> Bool {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("⚠️ [FileWatcher] Cannot check file changes - no watched file path")
            return false
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let currentModDate = attributes[.modificationDate] as? Date

            AppLogger.shared.log(
                "📁 [FileWatcher] Checking file modification: current=\(currentModDate?.description ?? "nil"), last=\(lastModificationDate?.description ?? "nil")"
            )

            // If we don't have a previous date, consider it changed
            guard let lastDate = lastModificationDate else {
                AppLogger.shared.log(
                    "📁 [FileWatcher] No previous modification date - considering file changed"
                )
                lastModificationDate = currentModDate
                return true
            }

            // Check if modification date has actually changed
            let hasChanged = currentModDate != lastDate

            if hasChanged {
                lastModificationDate = currentModDate
                AppLogger.shared.log(
                    "✅ [FileWatcher] File modification confirmed at \(currentModDate?.description ?? "unknown")"
                )
            } else {
                AppLogger.shared.log("📁 [FileWatcher] File modification date unchanged - no actual change")
            }

            return hasChanged
        } catch {
            AppLogger.shared.log("❌ [FileWatcher] Error checking file modification for \(path): \(error)")
            return false
        }
    }

    private func processFileChange() async {
        guard let path = watchedFilePath else {
            AppLogger.shared.log("⚠️ [FileWatcher] Cannot process file change - no watched file path")
            return
        }

        AppLogger.shared.log("📁 [FileWatcher] Processing debounced file change for: \(path)")

        // Check if file still exists (important for atomic writes)
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.shared.log("⚠️ [FileWatcher] File no longer exists during processing: \(path)")

            // Switch to directory monitoring to watch for recreation
            fileMonitorSource?.cancel()
            fileMonitorSource = nil
            isWatching = false
            setupDirectoryMonitoring()
            return
        }

        if pendingAtomicWriteEvent {
            pendingAtomicWriteEvent = false
            AppLogger.shared.log("📁 [FileWatcher] Atomic write detected - forcing change callback")
        } else {
            // Check if file actually changed (avoid false positives)
            guard hasFileActuallyChanged() else {
                AppLogger.shared.log("📁 [FileWatcher] No actual file changes detected - skipping callback")
                return
            }
        }

        // Get file size for logging
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            AppLogger.shared.log(
                "📁 [FileWatcher] Triggering file change callback for file (\(fileSize) bytes)"
            )
        } catch {
            AppLogger.shared.log("📁 [FileWatcher] Triggering file change callback (size unknown)")
        }

        // Trigger the callback (already on MainActor)
        await onFileChanged?()
        AppLogger.shared.log("✅ [FileWatcher] File change callback completed")
    }
}

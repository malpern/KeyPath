// Watches kindaVim's published mode state from
// `~/Library/Application Support/kindaVim/environment.json` and exposes
// the current mode as an Observable property the overlay can react to.
//
// kindaVim writes the file on every mode change (see
// https://docs.kindavim.app/integrations/json-file). The file path is
// stable across kindaVim versions and survives app restarts, which makes
// it more robust than the older NSDistributedNotification API some
// users have reported issues with on newer macOS releases.

import Foundation
import KeyPathCore

@MainActor
@Observable
final class KindaVimModeMonitor {
    static let shared = KindaVimModeMonitor()

    enum Mode: String, Sendable, Equatable {
        case insert
        case normal
        case visual
        case operatorPending = "operator-pending"

        public var displayLabel: String {
            switch self {
            case .insert: "Insert"
            case .normal: "Normal"
            case .visual: "Visual"
            case .operatorPending: "Op"
            }
        }
    }

    /// Current mode, or nil if kindaVim isn't running / file not present yet.
    private(set) var mode: Mode?

    /// True if the environment file exists at all (kindaVim was ever launched).
    private(set) var environmentFileExists: Bool = false

    @ObservationIgnored
    private var fileSource: DispatchSourceFileSystemObject?

    @ObservationIgnored
    private var fileDescriptor: Int32 = -1

    @ObservationIgnored
    private var directorySource: DispatchSourceFileSystemObject?

    @ObservationIgnored
    private var directoryDescriptor: Int32 = -1

    @ObservationIgnored
    private var notificationObservers: [NSObjectProtocol] = []

    static let environmentFileURL: URL = {
        let appSupport = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("kindaVim", isDirectory: true)
            .appendingPathComponent("environment.json")
    }()

    /// Start observing the kindaVim environment file. Idempotent.
    func start() {
        guard fileSource == nil, directorySource == nil else { return }
        AppLogger.shared.log("👀 [KindaVimMonitor] Starting")
        readCurrentState()
        if FileManager.default.fileExists(atPath: Self.environmentFileURL.path) {
            attachFileWatcher()
        } else {
            attachDirectoryWatcher()
        }
        attachDistributedNotificationFallback()
    }

    /// Stop observing. Idempotent.
    func stop() {
        AppLogger.shared.log("🛑 [KindaVimMonitor] Stopping")
        detachFileWatcher()
        detachDirectoryWatcher()
        for token in notificationObservers {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        notificationObservers.removeAll()
        mode = nil
        environmentFileExists = false
    }

    // MARK: - File watching

    private func attachFileWatcher() {
        let url = Self.environmentFileURL
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            AppLogger.shared.warn("⚠️ [KindaVimMonitor] open() failed for \(url.path)")
            return
        }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            // Re-read on any write / extend.
            if events.contains(.write) || events.contains(.extend) {
                self.readCurrentState()
            }
            // File replaced or moved (atomic write) — re-attach.
            if events.contains(.delete) || events.contains(.rename) {
                self.detachFileWatcher()
                self.attachDirectoryWatcher()
                self.readCurrentState()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileSource = source
    }

    private func detachFileWatcher() {
        fileSource?.cancel()
        fileSource = nil
        fileDescriptor = -1
    }

    /// Watches the parent directory so we notice when kindaVim creates the
    /// environment.json for the first time after KeyPath launches before kV.
    private func attachDirectoryWatcher() {
        let dir = Self.environmentFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: Self.environmentFileURL.path) {
                self.detachDirectoryWatcher()
                self.attachFileWatcher()
                self.readCurrentState()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func detachDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryDescriptor = -1
    }

    private func readCurrentState() {
        let url = Self.environmentFileURL
        guard let data = try? Data(contentsOf: url) else {
            environmentFileExists = false
            mode = nil
            return
        }
        environmentFileExists = true
        struct Payload: Decodable { let mode: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let parsed = Mode(rawValue: payload.mode)
        else {
            mode = nil
            return
        }
        if mode != parsed {
            mode = parsed
            AppLogger.shared.log("👀 [KindaVimMonitor] mode → \(parsed.rawValue)")
        }
    }

    // MARK: - Distributed notification fallback

    /// Subscribe to kindaVim's `kindaVimDidEnter*Mode` distributed
    /// notifications as a belt-and-suspenders signal. The JSON file is
    /// the primary path; this catches the rare case where file events
    /// aren't delivered (some users have reported flakiness on newer
    /// macOS releases).
    private func attachDistributedNotificationFallback() {
        let center = DistributedNotificationCenter.default()
        let pairs: [(name: String, mode: Mode)] = [
            ("kindaVimDidEnterInsertMode", .insert),
            ("kindaVimDidEnterNormalMode", .normal),
            ("kindaVimDidEnterVisualMode", .visual),
            ("kindaVimDidEnterOperatorPendingMode", .operatorPending)
        ]
        for (name, target) in pairs {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.mode != target {
                        self.mode = target
                        AppLogger.shared.log("👀 [KindaVimMonitor] (notif) mode → \(target.rawValue)")
                    }
                }
            }
            notificationObservers.append(token)
        }
    }
}

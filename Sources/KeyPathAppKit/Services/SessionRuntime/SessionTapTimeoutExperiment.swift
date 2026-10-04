#if KEYPATH_TAP_TIMEOUT_EXPERIMENT
    import CryptoKit
    import Darwin
    import Foundation

    /// Experimental builds only. No command means no delay; one file is admitted once.
    final class SessionTapTimeoutExperiment {
        struct Identity: Equatable {
            let pid: Int32
            let uid: UInt32
            let parentPID: Int32
            let nonce: String
            let binarySHA256: String
            let configSHA256: String
        }

        struct Command: Codable {
            let version: Int
            let sequence: Int
            let pid: Int32
            let uid: UInt32
            let parentPID: Int32
            let nonce: String
            let binarySHA256: String
            let configSHA256: String
            let expiresEpoch: Int
            let durationMillis: Int
            let triggerKeyCode: Int
        }

        private let identity: Identity
        private let directory: URL
        private var inspected = false
        private var pending: Command?
        private var spent = false

        init(reportURL: URL, nonce: String, parentPID: Int32, configPath: String) throws {
            guard let executable = Bundle.main.executableURL else { throw Refusal.invalid }
            identity = try Identity(pid: getpid(), uid: getuid(), parentPID: parentPID, nonce: nonce,
                                    binarySHA256: Self.digest(executable),
                                    configSHA256: Self.digest(URL(fileURLWithPath: configPath)))
            directory = reportURL.deletingLastPathComponent()
        }

        // Used by the standalone admission tests; production always captures its actual identity.
        init(identity: Identity, directory: URL) {
            self.identity = identity
            self.directory = directory
        }

        static func digest(_ path: URL) throws -> String {
            let data = try Data(contentsOf: path)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        static func decode(_ data: Data, identity: Identity, now: TimeInterval) throws -> Command {
            let object = try JSONSerialization.jsonObject(with: data)
            let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard data == canonical, let fields = object as? [String: Any],
                  Set(fields.keys) == Set(["version", "sequence", "pid", "uid", "parentPID", "nonce",
                                           "binarySHA256", "configSHA256", "expiresEpoch", "durationMillis", "triggerKeyCode"])
            else { throw Refusal.invalid }
            let command = try JSONDecoder().decode(Command.self, from: data)
            guard command.version == 1, command.sequence == 1, command.uid == 502,
                  command.pid == identity.pid, command.uid == identity.uid,
                  command.parentPID == identity.parentPID, command.parentPID > 0,
                  command.nonce == identity.nonce, UUID(uuidString: command.nonce) != nil,
                  command.binarySHA256 == identity.binarySHA256, command.configSHA256 == identity.configSHA256,
                  command.triggerKeyCode == 11, (1 ... 1000).contains(command.durationMillis),
                  Double(command.expiresEpoch) > now, Double(command.expiresEpoch) <= now + 30
            else { throw Refusal.invalid }
            return command
        }

        enum Refusal: Error { case invalid }

        private func directoryIsOwned() -> Bool {
            var info = stat()
            return directory.path == directory.resolvingSymlinksInPath().path
                && lstat(directory.path, &info) == 0 && info.st_uid == identity.uid
                && info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o777 == 0o700
        }

        /// File I/O and decoding happen on the ordinary timer, outside the event callback.
        func prepare(now: TimeInterval) {
            guard !inspected, identity.uid == 502, directoryIsOwned() else { return }
            let path = directory.appendingPathComponent("tap-timeout-command.json").path
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { return }
            defer { close(fd) }
            inspected = true // A malformed or changed command cannot be replaced and retried.
            var first = stat()
            guard fstat(fd, &first) == 0, first.st_uid == identity.uid,
                  first.st_mode & S_IFMT == S_IFREG, first.st_mode & 0o777 == 0o600,
                  first.st_nlink == 1, first.st_size > 0, first.st_size <= 4096 else { return }
            var bytes = [UInt8](repeating: 0, count: Int(first.st_size))
            let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            var second = stat(), named = stat()
            guard count == bytes.count, fstat(fd, &second) == 0, lstat(path, &named) == 0,
                  Self.same(first, second), Self.same(first, named), directoryIsOwned() else { return }
            pending = try? Self.decode(Data(bytes), identity: identity, now: now)
        }

        private static func same(_ a: stat, _ b: stat) -> Bool {
            a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_gid == b.st_gid
                && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink && a.st_size == b.st_size
                && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
                && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
        }

        /// Only the registered real-event callback calls this. No synthetic timeout notification.
        func delayIfAdmitted(keyCode: Int, keyDown: Bool, repeatEvent: Bool, mapped: Bool,
                             heldUsages: [UInt32], reportAge: TimeInterval, now: TimeInterval,
                             environmentCurrent: Bool, secureInput: Bool,
                             sleep: (UInt32) -> Void = { usleep($0) }) {
            guard !spent, let command = pending, keyCode == command.triggerKeyCode, keyDown, !repeatEvent,
                  !mapped, heldUsages == [4], environmentCurrent, !secureInput,
                  now < Double(command.expiresEpoch), reportAge >= 0,
                  reportAge + Double(command.durationMillis) / 1000 + 0.25 < 2,
                  getpid() == identity.pid, getuid() == identity.uid, kill(identity.parentPID, 0) == 0,
                  directoryIsOwned() else { return }
            spent = true
            pending = nil
            guard publish("entered", durationMillis: command.durationMillis) else { return }
            sleep(UInt32(command.durationMillis) * 1000)
            _ = publish("returned", durationMillis: command.durationMillis)
        }

        private func publish(_ phase: String, durationMillis: Int) -> Bool {
            guard directoryIsOwned() else { return false }
            let path = directory.appendingPathComponent("tap-timeout-delay-\(phase).json").path
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            let object: [String: Any] = ["version": 1, "sequence": 1, "pid": identity.pid,
                                         "uid": identity.uid, "parentPID": identity.parentPID,
                                         "nonce": identity.nonce, "phase": phase, "durationMillis": durationMillis,
                                         "monotonicNanos": clock_gettime_nsec_np(CLOCK_UPTIME_RAW)]
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return false }
            guard data.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == data.count, fsync(fd) == 0 else { return false }
            let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard parent >= 0 else { return false }
            defer { close(parent) }
            return fsync(parent) == 0
        }
    }
#endif

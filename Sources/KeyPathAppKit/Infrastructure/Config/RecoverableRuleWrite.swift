import Darwin
import Foundation

/// The file-persistence portion of a rule edit. Call off the main actor.
/// Fixed caller-supplied roles resolve journal entries; journal data cannot choose
/// arbitrary target paths. Staged writes retain recovery through runtime application;
/// ordinary rule writes still commit at the file-persistence boundary.
enum RecoverableRuleWrite {
    enum Scope: Sendable, Equatable {
        case rules
        case appKeymaps
        case packRules
        case rawConfig

        var roles: Set<String> {
            switch self {
            case .rules: ["config", "collections", "customRules"]
            case .appKeymaps: ["config", "appKeymaps", "appInclude"]
            case .packRules: ["config", "collections", "customRules", "installedPacks"]
            case .rawConfig: ["config"]
            }
        }
    }

    struct PendingWrite: Sendable {
        fileprivate let files: [String: URL]
        fileprivate let directory: URL
        fileprivate let scope: Scope
        fileprivate let journal: Journal
        fileprivate let preferences: PreferenceDefaults?
    }

    struct Entry: Codable, Equatable, Sendable {
        let role: String
        let path: String
        let before: Data?
        let after: Data
    }

    struct Journal: Codable, Equatable, Sendable {
        let version: Int
        var committed: Bool
        let entries: [Entry]
        let preferences: [PreferenceEntry]

        init(version: Int, committed: Bool, entries: [Entry], preferences: [PreferenceEntry] = []) {
            self.version = version
            self.committed = committed
            self.entries = entries
            self.preferences = preferences
        }

        private enum CodingKeys: String, CodingKey { case version, committed, entries, preferences }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            committed = try container.decode(Bool.self, forKey: .committed)
            entries = try container.decode([Entry].self, forKey: .entries)
            preferences = try container.decodeIfPresent([PreferenceEntry].self, forKey: .preferences) ?? []
        }
    }

    struct PreferenceEntry: Codable, Equatable, Sendable {
        let role: PreferenceRole
        let before: Data?
        let after: Data
    }

    struct PreferenceChange: Sendable {
        let role: PreferenceRole
        let before: Data?
        let after: Data

        static func leader(before: Data?, after: Data) throws -> Self {
            try .init(
                role: .leader,
                before: before.map(requiredPreferenceData),
                after: requiredPreferenceData(after)
            )
        }
    }

    enum PreferenceRole: Codable, Hashable, Sendable {
        case leader

        var key: String {
            switch self {
            case .leader: PreferencesService.leaderKeyPreferenceKey
            }
        }
    }

    struct PreferenceDefaults: @unchecked Sendable {
        let value: UserDefaults
        init(_ value: UserDefaults) {
            self.value = value
        }
    }

    struct WriteFailure: LocalizedError {
        let cause: Error
        let recoveryError: Error?

        var errorDescription: String? {
            if let recoveryError {
                return "Rule files could not be saved: \(cause.localizedDescription). Recovery also failed: \(recoveryError.localizedDescription)"
            }
            return "Rule files could not be saved; the prior files were restored: \(cause.localizedDescription)"
        }
    }

    enum Failure: LocalizedError {
        case invalidJournal
        case changedFile(String)
        case changedPreference(String)
        case systemCall(String, Int32)

        var errorDescription: String? {
            switch self {
            case .invalidJournal: "The pending rule-write journal does not match these rule stores."
            case let .changedFile(role): "The \(role) file changed outside this operation. Recovery was stopped to preserve it."
            case let .changedPreference(key): "The \(key) preference changed outside this operation. Recovery was stopped to preserve it."
            case let .systemCall(operation, code): "Rule-write \(operation) failed (errno \(code))."
            }
        }
    }

    static func apply(
        files: [String: URL], contents: [String: Data], directory: URL,
        writeFile: (Data, URL) throws -> Void = durableWrite
    ) throws {
        _ = try write(files: files, contents: contents, directory: directory, scope: .rules,
                      commitImmediately: true, writeFile: writeFile)
    }

    /// Retain the prior revision until the caller classifies runtime application.
    static func stage(
        files: [String: URL], contents: [String: Data], directory: URL, scope: Scope,
        expectedBefore: [String: Data]? = nil,
        preferences: UserDefaults? = nil, preferenceChanges: [PreferenceChange] = [],
        synchronizePreferences: (PreferenceDefaults) -> Bool = { $0.value.synchronize() },
        writeFile: (Data, URL) throws -> Void = durableWrite
    ) throws -> PendingWrite {
        try write(files: files, contents: contents, directory: directory, scope: scope,
                  commitImmediately: false, expectedBefore: expectedBefore,
                  preferences: preferences, preferenceChanges: preferenceChanges,
                  synchronizePreferences: synchronizePreferences, writeFile: writeFile)
    }

    private static func write(
        files: [String: URL], contents: [String: Data], directory: URL, scope: Scope,
        commitImmediately: Bool, expectedBefore: [String: Data]? = nil,
        preferences: UserDefaults? = nil, preferenceChanges: [PreferenceChange] = [],
        synchronizePreferences: (PreferenceDefaults) -> Bool = { $0.value.synchronize() },
        writeFile: (Data, URL) throws -> Void
    ) throws -> PendingWrite {
        try validateFiles(files, directory: directory, scope: scope)
        return try withLock(directory: directory) {
            try recoverLocked(files: files, directory: directory, scope: scope,
                              preferences: preferences, writeFile: writeFile)
            if let expectedBefore {
                for (role, url) in files {
                    guard try read(url) == expectedBefore[role] else { throw Failure.changedFile(role) }
                }
            }
            guard Set(files.keys) == Set(contents.keys),
                  Set(files.values.map(\.standardizedFileURL)).count == files.count,
                  !files.isEmpty
            else { throw Failure.invalidJournal }
            let entries = try files.keys.sorted().map { role in
                try Entry(role: role, path: files[role]!.standardizedFileURL.path, before: read(files[role]!), after: contents[role]!)
            }
            guard preferenceChanges.isEmpty || preferences != nil,
                  Set(preferenceChanges.map(\.role)).count == preferenceChanges.count
            else { throw Failure.invalidJournal }
            let preferenceEntries = try preferenceChanges.map { change in
                guard try readPreference(change.role, from: preferences) == change.before else {
                    throw Failure.changedPreference(change.role.key)
                }
                return PreferenceEntry(
                    role: change.role,
                    before: change.before,
                    after: change.after
                )
            }
            var journal = Journal(version: 2, committed: false, entries: entries, preferences: preferenceEntries)
            try durableWrite(JSONEncoder().encode(journal), journalURL(directory, scope: scope))
            var committing = false
            do {
                for entry in entries {
                    let url = files[entry.role]!
                    guard try read(url) == entry.before else { throw Failure.changedFile(entry.role) }
                    try writeFile(entry.after, url)
                }
                if let preferences, !preferenceEntries.isEmpty {
                    for entry in preferenceEntries {
                        guard try readPreference(entry.role, from: preferences) == entry.before else {
                            throw Failure.changedPreference(entry.role.key)
                        }
                    }
                    for change in preferenceChanges {
                        try writePreference(change.after, role: change.role, to: preferences)
                    }
                    guard synchronizePreferences(PreferenceDefaults(preferences)) else {
                        throw Failure.systemCall("preference synchronize", EIO)
                    }
                    try requireAfterPreferences(preferenceEntries, in: preferences)
                }
                // A committed journal may safely be cleaned up at the next startup.
                if commitImmediately {
                    committing = true
                    journal.committed = true
                    try durableWrite(JSONEncoder().encode(journal), journalURL(directory, scope: scope))
                }
            } catch {
                let cause = error
                do {
                    if committing {
                        // The marker write may have replaced the journal before
                        // fsync failed. Re-establish rollback intent durably first.
                        journal.committed = false
                        try durableWrite(JSONEncoder().encode(journal), journalURL(directory, scope: scope))
                    }
                    try recoverLocked(files: files, directory: directory, scope: scope,
                                      preferences: preferences, writeFile: writeFile)
                } catch {
                    throw WriteFailure(cause: cause, recoveryError: error)
                }
                throw WriteFailure(cause: cause, recoveryError: nil)
            }
            // Persistence is committed even if journal cleanup must be retried.
            if commitImmediately { try? removeJournal(directory, scope: scope) }
            return PendingWrite(
                files: files, directory: directory, scope: scope, journal: journal,
                preferences: preferences.map(PreferenceDefaults.init)
            )
        }
    }

    static func commit(_ pending: PendingWrite) throws {
        try withLock(directory: pending.directory) {
            try validatePending(pending)
            for entry in pending.journal.entries {
                guard try read(pending.files[entry.role]!) == entry.after else {
                    throw Failure.changedFile(entry.role)
                }
            }
            try requireAfterPreferences(pending.journal.preferences, in: pending.preferences?.value)
            var committed = pending.journal
            committed.committed = true
            let url = journalURL(pending.directory, scope: pending.scope)
            do {
                try durableWrite(JSONEncoder().encode(committed), url)
            } catch {
                let cause = error
                do { try durableWrite(JSONEncoder().encode(pending.journal), url) }
                catch { throw WriteFailure(cause: cause, recoveryError: error) }
                throw cause
            }
            try? removeJournal(pending.directory, scope: pending.scope)
        }
    }

    static func rollback(_ pending: PendingWrite) throws {
        try withLock(directory: pending.directory) {
            try validatePending(pending)
            try recoverLocked(files: pending.files, directory: pending.directory,
                              scope: pending.scope, preferences: pending.preferences?.value, writeFile: durableWrite)
        }
    }

    private static func validatePending(_ pending: PendingWrite) throws {
        try validateFiles(pending.files, directory: pending.directory, scope: pending.scope)
        guard !pending.journal.committed,
              let data = try read(journalURL(pending.directory, scope: pending.scope)),
              try JSONDecoder().decode(Journal.self, from: data) == pending.journal
        else { throw Failure.invalidJournal }
    }

    @discardableResult
    static func recover(files: [String: URL], directory: URL, scope: Scope = .rules,
                        preferences: UserDefaults? = nil) throws -> Bool
    {
        try validateFiles(files, directory: directory, scope: scope)
        return try withLock(directory: directory) {
            let hadJournal = try read(journalURL(directory, scope: scope)) != nil
            try recoverLocked(files: files, directory: directory, scope: scope,
                              preferences: preferences, writeFile: durableWrite)
            return hadJournal
        }
    }

    private static func recoverLocked(
        files: [String: URL], directory: URL, scope: Scope, preferences: UserDefaults? = nil,
        writeFile: (Data, URL) throws -> Void
    ) throws {
        let url = journalURL(directory, scope: scope)
        guard let data = try read(url) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1 || journal.version == 2,
              journal.entries.count == files.count,
              Set(journal.entries.map(\.role)) == Set(files.keys),
              journal.entries.allSatisfy({ files[$0.role]?.standardizedFileURL.path == $0.path }),
              Set(files.values.map(\.standardizedFileURL)).count == files.count
        else { throw Failure.invalidJournal }
        if journal.committed {
            try removeJournal(directory, scope: scope)
            return
        }
        // Check the whole set first so a conflict does not cause partial recovery.
        for entry in journal.entries {
            let actual = try read(files[entry.role]!)
            guard actual == entry.before || actual == entry.after else {
                throw Failure.changedFile(entry.role)
            }
        }
        try validatePreferences(journal.preferences, in: preferences)
        for entry in journal.entries {
            let target = files[entry.role]!
            let actual = try read(target)
            guard actual == entry.before || actual == entry.after else {
                throw Failure.changedFile(entry.role)
            }
            if actual == entry.before { continue }
            if let previous = entry.before {
                try writeFile(previous, target)
            } else {
                try FileManager.default.removeItem(at: target)
                try syncDirectory(target.deletingLastPathComponent())
            }
        }
        if let preferences, !journal.preferences.isEmpty {
            for entry in journal.preferences where try readPreference(entry.role, from: preferences) == entry.after {
                if let before = entry.before {
                    try writePreference(before, role: entry.role, to: preferences)
                } else {
                    preferences.removeObject(forKey: entry.role.key)
                }
            }
            guard preferences.synchronize() else { throw Failure.systemCall("preference synchronize", EIO) }
            for entry in journal.preferences {
                let actual = try readPreference(entry.role, from: preferences)
                guard actual == entry.before else {
                    throw Failure.changedPreference(entry.role.key)
                }
            }
        }
        try removeJournal(directory, scope: scope)
    }

    private static func validatePreferences(_ entries: [PreferenceEntry], in defaults: UserDefaults?) throws {
        guard entries.isEmpty || defaults != nil else { throw Failure.invalidJournal }
        guard let defaults else { return }
        for entry in entries {
            let actual = try readPreference(entry.role, from: defaults)
            guard actual == entry.before || actual == entry.after else {
                throw Failure.changedPreference(entry.role.key)
            }
        }
    }

    private static func requireAfterPreferences(_ entries: [PreferenceEntry], in defaults: UserDefaults?) throws {
        guard entries.isEmpty || defaults != nil else { throw Failure.invalidJournal }
        guard let defaults else { return }
        for entry in entries {
            let actual = try readPreference(entry.role, from: defaults)
            guard actual == entry.after else {
                throw Failure.changedPreference(entry.role.key)
            }
        }
    }

    private static func preferenceData(_ value: Any?) throws -> Data? {
        guard let value else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private static func requiredPreferenceData(_ value: Any) throws -> Data {
        guard let data = try preferenceData(value) else { throw Failure.invalidJournal }
        return data
    }

    private static func preferenceValue(_ data: Data) throws -> Any {
        try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private static func readPreference(_ role: PreferenceRole, from defaults: UserDefaults?) throws -> Data? {
        guard let defaults else { return nil }
        return try preferenceData(defaults.object(forKey: role.key))
    }

    private static func writePreference(_ data: Data, role: PreferenceRole, to defaults: UserDefaults) throws {
        try defaults.set(preferenceValue(data), forKey: role.key)
    }

    static func journalURL(_ directory: URL, scope: Scope = .rules) -> URL {
        let name = switch scope {
        case .rules: ".keypath-rule-write.json"
        case .appKeymaps: ".keypath-app-write.json"
        case .packRules: ".keypath-pack-rule-write.json"
        case .rawConfig: ".keypath-raw-write.json"
        }
        return directory.appendingPathComponent(name)
    }

    private static func validateFiles(_ files: [String: URL], directory: URL, scope: Scope) throws {
        let targets = Set(files.values.map(\.standardizedFileURL))
        let reserved = Set([
            journalURL(directory),
            journalURL(directory, scope: .appKeymaps),
            journalURL(directory, scope: .packRules),
            journalURL(directory, scope: .rawConfig),
            directory.appendingPathComponent(".keypath-rule-write.lock")
        ]
        .map(\.standardizedFileURL))
        guard Set(files.keys) == scope.roles,
              targets.count == files.count, targets.isDisjoint(with: reserved)
        else { throw Failure.invalidJournal }
    }

    private static func removeJournal(_ directory: URL, scope: Scope) throws {
        try FileManager.default.removeItem(at: journalURL(directory, scope: scope))
        try syncDirectory(directory)
    }

    private static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    static func durableWrite(_ data: Data, _ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.systemCall("open", errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure.systemCall("fsync", errno) }
        try syncDirectory(parent)
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.systemCall("open directory", errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure.systemCall("fsync directory", errno) }
    }

    private static func withLock<T>(directory: URL, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".keypath-rule-write.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.systemCall("open lock", errno) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw Failure.systemCall("lock", errno) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

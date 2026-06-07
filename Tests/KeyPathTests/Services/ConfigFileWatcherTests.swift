import Foundation
@testable import KeyPathAppKit
import Testing

@Suite("ConfigFileWatcher")
struct ConfigFileWatcherTests {
    private func makeTempFile() throws -> (dir: URL, path: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("config.kbd").path
        FileManager.default.createFile(atPath: path, contents: Data("initial".utf8))
        return (dir, path)
    }

    @Test("isActive is false before startWatching")
    func isActiveInitially() {
        let watcher = ConfigFileWatcher()
        #expect(watcher.isActive == false)
    }

    @Test("isActive is true after startWatching")
    @MainActor
    func isActiveAfterStart() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("stopWatching sets isActive to false")
    @MainActor
    func stopWatchingClearsActive() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        watcher.stopWatching()
        #expect(watcher.isActive == false)
    }

    @Test("starting a new watch stops the previous one")
    @MainActor
    func restartWatchStopsPrevious() throws {
        let (dir, path1) = try makeTempFile()
        let path2 = dir.appendingPathComponent("config2.kbd").path
        FileManager.default.createFile(atPath: path2, contents: Data("second".utf8))

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path1) {}
        #expect(watcher.isActive == true)

        watcher.startWatching(path: path2) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("suppressEvents prevents callback during suppression window")
    @MainActor
    func suppressionPreventsCallback() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()

        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }
        watcher.suppressEvents(for: 5.0, reason: "test")

        try "suppressed-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.simulateFileEventForTesting()

        #expect(callbackCount == 0)
        watcher.stopWatching()
    }

    @Test("watches directory when file does not exist yet")
    @MainActor
    func watchesDirectoryForNonExistentFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("not-yet.kbd").path

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("stopWatching is idempotent")
    @MainActor
    func stopWatchingIdempotent() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        watcher.stopWatching()
        watcher.stopWatching()
        #expect(watcher.isActive == false)
    }
}

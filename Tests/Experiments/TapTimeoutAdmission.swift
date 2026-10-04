import Foundation
import Darwin

@main
struct TapTimeoutAdmissionTests {
    static func main() throws {
        let identity = SessionTapTimeoutExperiment.Identity(pid: 123, uid: 502, parentPID: 456,
            nonce: "80CD1C8D-9C99-4A09-AE0F-56C561DD21CA", binarySHA256: String(repeating: "a", count: 64),
            configSHA256: String(repeating: "b", count: 64))
        let now = Date().timeIntervalSince1970
        let valid: [String: Any] = ["version": 1, "sequence": 1, "pid": 123, "uid": 502, "parentPID": 456,
            "nonce": identity.nonce, "binarySHA256": identity.binarySHA256, "configSHA256": identity.configSHA256,
            "expiresEpoch": Int(now) + 10, "durationMillis": 100, "triggerKeyCode": 11]
        func encoded(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        let admitted = try SessionTapTimeoutExperiment.decode(encoded(valid), identity: identity, now: now)
        precondition(admitted.durationMillis == 100)
        var refused = 0
        for (key, value) in [("sequence", 2 as Any), ("uid", 501), ("pid", 124), ("parentPID", 457),
                             ("nonce", UUID().uuidString), ("binarySHA256", String(repeating: "c", count: 64)),
                             ("configSHA256", String(repeating: "c", count: 64)), ("durationMillis", 0),
                             ("durationMillis", 1001), ("durationMillis", true), ("triggerKeyCode", 12),
                             ("expiresEpoch", Int(now) - 1), ("expiresEpoch", Int(now) + 31), ("extra", "inert")] {
            var object = valid; object[key] = value
            do { _ = try SessionTapTimeoutExperiment.decode(encoded(object), identity: identity, now: now)
                 fatalError("adverse command admitted") } catch { refused += 1 }
        }
        var duplicate = String(data: try encoded(valid), encoding: .utf8)!
        duplicate.insert(contentsOf: "\"sequence\":1,", at: duplicate.index(after: duplicate.startIndex))
        do { _ = try SessionTapTimeoutExperiment.decode(Data(duplicate.utf8), identity: identity, now: now)
             fatalError("duplicate command admitted") } catch { refused += 1 }
        // Actual runtime class: no control file cannot delay any event, even with matching held output.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let hook = SessionTapTimeoutExperiment(identity: identity, directory: directory)
        hook.prepare(now: now)
        var sleeps = 0
        for _ in 0 ..< 2 {
            hook.delayIfAdmitted(keyCode: 11, keyDown: true, repeatEvent: false, mapped: false,
                                 heldUsages: [4], reportAge: 0.1, now: now,
                                 environmentCurrent: true, secureInput: false, sleep: { _ in sleeps += 1 })
        }
        precondition(sleeps == 0)
        print("tapTimeoutAdmissionRefusals=\(refused) defaultOff=true actualOSTimeoutUntested=true")
    }
}

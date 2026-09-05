import Foundation
@testable import KeyPathAppKit
import XCTest

final class RecoverableRuleWriteTests: XCTestCase {
    private enum Injected: Error { case write, rollback }

    private func fixture(_ test: (URL, [String: URL], [String: Data], [String: Data]) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = Dictionary(uniqueKeysWithValues: ["config", "collections", "customRules"].map {
            ($0, directory.appendingPathComponent($0))
        })
        let old = files.mapValues { Data("old \($0.lastPathComponent)".utf8) }
        let new = files.mapValues { Data("new \($0.lastPathComponent)".utf8) }
        for (role, url) in files {
            try old[role]!.write(to: url)
        }
        try test(directory, files, old, new)
    }

    private func assertFiles(_ files: [String: URL], equal contents: [String: Data], file: StaticString = #filePath, line: UInt = #line) throws {
        for (role, url) in files {
            XCTAssertEqual(try Data(contentsOf: url), contents[role], file: file, line: line)
        }
    }

    private func journal(_ directory: URL, files: [String: URL], old: [String: Data], new: [String: Data], committed: Bool = false) throws {
        let entries = files.keys.sorted().map {
            RecoverableRuleWrite.Entry(role: $0, path: files[$0]!.path, before: old[$0], after: new[$0]!)
        }
        let journal = RecoverableRuleWrite.Journal(version: 1, committed: committed, entries: entries)
        try JSONEncoder().encode(journal).write(to: RecoverableRuleWrite.journalURL(directory), options: .atomic)
    }

    func testStagingRefusesARevisionChangedAfterSourceLoading() throws {
        try fixture { directory, files, old, new in
            let external = Data("external edit".utf8)
            try external.write(to: files["config"]!)
            XCTAssertThrowsError(try RecoverableRuleWrite.stage(files: files, contents: new, directory: directory, scope: .rules, expectedBefore: old))
            var expected = old
            expected["config"] = external
            try assertFiles(files, equal: expected)
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
        }
    }

    func testCommittedReceiptCannotLaterRollBackAnotherRevision() throws {
        try fixture { directory, files, old, new in
            let first = try RecoverableRuleWrite.stage(files: files, contents: new, directory: directory, scope: .rules)
            try RecoverableRuleWrite.commit(first)
            let second = try RecoverableRuleWrite.stage(files: files, contents: old, directory: directory, scope: .rules)
            XCTAssertThrowsError(try RecoverableRuleWrite.rollback(first))
            try assertFiles(files, equal: old)
            try RecoverableRuleWrite.rollback(second)
            try assertFiles(files, equal: new)
        }
    }

    func testSuccessfulCommitWritesAllFilesAndRemovesJournal() throws {
        try fixture { directory, files, _, new in
            try RecoverableRuleWrite.apply(files: files, contents: new, directory: directory)
            try assertFiles(files, equal: new)
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
        }
    }

    func testFailureAfterEachWriteRestoresEveryPreviousFile() throws {
        for failAfter in 1 ... 3 {
            try fixture { directory, files, old, new in
                var writes = 0
                XCTAssertThrowsError(try RecoverableRuleWrite.apply(files: files, contents: new, directory: directory) { data, url in
                    try RecoverableRuleWrite.durableWrite(data, url)
                    writes += 1
                    if writes == failAfter { throw Injected.write }
                }) { error in
                    guard let failure = error as? RecoverableRuleWrite.WriteFailure else { return XCTFail("Missing recovery outcome") }
                    XCTAssertTrue(failure.cause is Injected)
                    XCTAssertNil(failure.recoveryError)
                }
                try assertFiles(files, equal: old)
                XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
            }
        }
    }

    func testInterruptedWriteRecoversAtEveryBoundary() throws {
        for written in 0 ... 3 {
            try fixture { directory, files, old, new in
                try journal(directory, files: files, old: old, new: new)
                for role in files.keys.sorted().prefix(written) {
                    try new[role]!.write(to: files[role]!, options: .atomic)
                }
                XCTAssertTrue(try RecoverableRuleWrite.recover(files: files, directory: directory))
                try assertFiles(files, equal: old)
                XCTAssertFalse(try RecoverableRuleWrite.recover(files: files, directory: directory), "Recovery is idempotent")
            }
        }
    }

    func testRecoveryRemovesFilesThatDidNotPreviouslyExist() throws {
        try fixture { directory, files, old, new in
            var previous = old
            previous.removeValue(forKey: "customRules")
            try journal(directory, files: files, old: previous, new: new)
            for (role, url) in files {
                try new[role]!.write(to: url)
            }
            try RecoverableRuleWrite.recover(files: files, directory: directory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: files["customRules"]!.path))
            for role in previous.keys {
                XCTAssertEqual(try Data(contentsOf: files[role]!), previous[role])
            }
        }
    }

    func testRollbackFailureRetainsJournalAndNextRecoveryCompletes() throws {
        try fixture { directory, files, old, new in
            var writes = 0
            XCTAssertThrowsError(try RecoverableRuleWrite.apply(files: files, contents: new, directory: directory) { data, url in
                writes += 1
                if writes == 2 { throw Injected.write }
                if writes == 3 { throw Injected.rollback }
                try RecoverableRuleWrite.durableWrite(data, url)
            }) { error in
                guard let failure = error as? RecoverableRuleWrite.WriteFailure else { return XCTFail("Missing recovery error") }
                XCTAssertNotNil(failure.recoveryError)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
            try RecoverableRuleWrite.recover(files: files, directory: directory)
            try assertFiles(files, equal: old)
        }
    }

    func testExternalEditStopsRecoveryWithoutOverwritingAnyFile() throws {
        try fixture { directory, files, old, new in
            try journal(directory, files: files, old: old, new: new)
            for (role, url) in files {
                try new[role]!.write(to: url)
            }
            let external = Data("external edit".utf8)
            try external.write(to: files["customRules"]!)
            XCTAssertThrowsError(try RecoverableRuleWrite.recover(files: files, directory: directory))
            XCTAssertEqual(try Data(contentsOf: files["customRules"]!), external)
            XCTAssertEqual(try Data(contentsOf: files["config"]!), new["config"])
            XCTAssertEqual(try Data(contentsOf: files["collections"]!), new["collections"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
            XCTAssertThrowsError(try RecoverableRuleWrite.apply(files: files, contents: old, directory: directory), "A new save must not discard unresolved recovery")
        }
    }

    func testCommittedJournalDoesNotUndoACompletedEditOrLaterExternalEdit() throws {
        try fixture { directory, files, old, new in
            try journal(directory, files: files, old: old, new: new, committed: true)
            for (role, url) in files {
                try new[role]!.write(to: url)
            }
            let external = Data("later edit".utf8)
            try external.write(to: files["config"]!)
            try RecoverableRuleWrite.recover(files: files, directory: directory)
            XCTAssertEqual(try Data(contentsOf: files["config"]!), external)
            XCTAssertEqual(try Data(contentsOf: files["collections"]!), new["collections"])
        }
    }

    func testJournalCannotRedirectRecoveryToOtherStores() throws {
        try fixture { directory, files, old, new in
            try journal(directory, files: files, old: old, new: new)
            var otherFiles = files
            otherFiles["config"] = directory.appendingPathComponent("different-config")
            try old["config"]!.write(to: otherFiles["config"]!)
            XCTAssertThrowsError(try RecoverableRuleWrite.recover(files: otherFiles, directory: directory))
            try assertFiles(files, equal: old)
        }
    }

    func testCorruptJournalFailsClosed() throws {
        try fixture { directory, files, old, new in
            try Data("broken json".utf8).write(to: RecoverableRuleWrite.journalURL(directory))
            XCTAssertThrowsError(try RecoverableRuleWrite.apply(files: files, contents: new, directory: directory))
            try assertFiles(files, equal: old)
        }
    }
}

@testable import KeyPathAppKit
import Foundation
import Testing

@Suite("WordlistStore")
struct WordlistStoreTests {
    @Test("User wordlist overrides bundle")
    func userWordlistPreferred() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-wordlist-tests", isDirectory: true)
        let supportURL = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wordlistURL = WordlistStore.userWordlistURL(id: "en_US", appSupportURL: supportURL)!

        try FileManager.default.createDirectory(at: wordlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "alpha\nbeta\n".write(to: wordlistURL, atomically: true, encoding: .utf8)

        let words = WordlistStore.loadWordlist(id: "en_US", appSupportURL: supportURL, bundle: .module)
        #expect(words == ["alpha", "beta"])
    }

    @Test("Parses wordlist contents")
    func parseContents() {
        let contents = """
        # comment

        hello
        world
        """
        let words = WordlistStore.parse(contents: contents)
        #expect(words == ["hello", "world"])
    }
}

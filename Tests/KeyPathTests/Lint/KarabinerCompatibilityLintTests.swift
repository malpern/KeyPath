import Foundation
import Testing

@Suite("Karabiner compatibility lint")
struct KarabinerCompatibilityLintTests {
    @Test("Removed Karabiner session monitor does not become a health signal again")
    func removedSessionMonitorDoesNotRegrow() throws {
        let roots = ["Sources", "Tests", "docs", "guides"]
        let obsoleteName = "karabiner_" + "session_monitor"

        for root in roots {
            let rootURL = LintScanner.path(root)
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: nil
            ) else {
                Issue.record("Could not enumerate \(root)")
                continue
            }
            let files = enumerator.compactMap { item -> URL? in
                guard let file = item as? URL else { return nil }
                return ["swift", "md"].contains(file.pathExtension) ? file : nil
            }
            for file in files where !file.path.contains("KarabinerCompatibilityLintTests.swift") {
                let contents = try String(contentsOf: file, encoding: .utf8)
                #expect(
                    !contents.contains(obsoleteName),
                    "Karabiner 16.1 removed the session monitor; use driver extension state, KeyPath launchd jobs, or karabiner_grabber conflict evidence instead: \(file.path)"
                )
            }
        }
    }
}

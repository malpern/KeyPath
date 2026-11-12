import Foundation
import XCTest

/// The wizard's pages get the app's services (its two app-side pages, the
/// external-Kanata operations, the Accessibility request) from `WizardHost` in
/// the SwiftUI environment. A host that shows the wizard without it fails
/// silently: Accessibility never asks macOS, Stop Kanata does nothing.
final class WizardHostInjectionLintTests: XCTestCase {
    func testEveryWizardHostInjectsTheAppServices() throws {
        let hosts = try LintScanner.swiftFiles(under: LintScanner.path("Sources/KeyPathAppKit")).filter {
            try String(contentsOf: $0, encoding: .utf8).contains("InstallationWizardView(")
        }
        XCTAssertFalse(hosts.isEmpty, "Expected the app to host the wizard somewhere")
        for file in hosts {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(
                contents.contains(".environment(\\.wizardHost, .app)"),
                "\(LintScanner.relativePath(file)) shows InstallationWizardView without .environment(\\.wizardHost, .app)"
            )
        }
    }
}

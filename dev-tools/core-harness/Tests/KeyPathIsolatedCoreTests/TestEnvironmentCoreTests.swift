import Foundation
import KeyPathCore
import Testing

@Suite("TestEnvironment Isolated Core Tests", .serialized)
struct TestEnvironmentCoreTests {
    @Test("Detects SwiftPM test execution")
    func detectsSwiftPMTestExecution() {
        #expect(TestEnvironment.isRunningTests)
        #expect(TestEnvironment.isTestMode)
    }

    @Test("Force test mode can be toggled")
    @MainActor
    func forceTestModeCanBeToggled() {
        let original = TestEnvironment.forceTestMode
        defer { TestEnvironment.forceTestMode = original }

        TestEnvironment.forceTestMode = true
        #expect(TestEnvironment.isTestMode)

        TestEnvironment.forceTestMode = false
        #expect(TestEnvironment.isTestMode)
    }
}

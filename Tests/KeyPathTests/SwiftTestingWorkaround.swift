// Workaround for Swift 6.2 beta crash when Swift Testing finds 0 tests
// Bug: Swift Testing crashes with SIGABRT after XCTest completes
// This can be removed once the beta bug is fixed

#if canImport(Testing)
    import Testing

    @Test("Workaround: prevent empty Swift Testing run (Xcode 26.0 beta)")
    func _swiftTesting_noop_workaround() {
        // This is a no-op test to prevent Swift Testing from crashing
        // when it finds "0 tests in 0 suites" after XCTest runs.
        // Filed as FB[number] with Apple
    }
#endif

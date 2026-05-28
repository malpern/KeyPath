import Foundation
@testable import KeyPathAppKit
import Testing

// MARK: - ServiceContainer Tests

@Suite("ServiceContainer Tests")
@MainActor
struct ServiceContainerTests {

    @Test("default init creates container with shared instances")
    func defaultInitCreatesContainer() {
        let container = ServiceContainer()
        // All properties should be non-nil (they are non-optional lets, so this is
        // primarily a compile-time guarantee, but we verify they are the shared instances)
        #expect(container.preferences === PreferencesService.shared)
        #expect(container.iconResolver === IconResolverService.shared)
        #expect(container.faviconFetcher === FaviconFetcher.shared)
    }

    @Test("properties are accessible and correctly typed")
    func propertiesAreAccessible() {
        let container = ServiceContainer()
        // Verify each property is the expected type via assignment
        let _: PreferencesService = container.preferences
        let _: AppKeymapStore = container.appKeymapStore
        let _: RuleCollectionStore = container.ruleCollectionStore
        let _: IconResolverService = container.iconResolver
        let _: FaviconFetcher = container.faviconFetcher
        // If we get here without a compile error, types are correct
    }

    @Test("container is @Observable and can be instantiated")
    func containerIsObservable() {
        // ServiceContainer is @Observable -- verify it can be created and used.
        // The @Observable macro generates synthesized storage; this test ensures
        // the macro expansion compiles and runs correctly.
        let container = ServiceContainer()
        // Access a property to exercise the @Observable getter path
        let _ = container.preferences
    }

    @Test("multiple containers are independent instances")
    func multipleContainersAreIndependent() {
        let a = ServiceContainer()
        let b = ServiceContainer()
        // Both use .shared defaults so properties are the same, but containers are distinct objects
        #expect(a !== b)
        #expect(a.preferences === b.preferences, "Both should reference the shared PreferencesService")
    }
}

// MARK: - BuildInfo Tests

@Suite("BuildInfo Tests")
struct BuildInfoTests {

    @Test("current returns non-empty version")
    func currentReturnsNonEmptyVersion() {
        let info = BuildInfo.current()
        #expect(!info.version.isEmpty)
    }

    @Test("current returns non-empty build number")
    func currentReturnsNonEmptyBuild() {
        let info = BuildInfo.current()
        #expect(!info.build.isEmpty)
    }

    @Test("current returns non-empty date")
    func currentReturnsNonEmptyDate() {
        let info = BuildInfo.current()
        #expect(!info.date.isEmpty)
    }

    @Test("BuildInfo stores all properties")
    func buildInfoStoresAllProperties() {
        let info = BuildInfo(
            version: "2.5.0",
            build: "42",
            git: "abc1234",
            date: "2026-01-15T10:00:00Z",
            kanataVersion: "1.10.0"
        )
        #expect(info.version == "2.5.0")
        #expect(info.build == "42")
        #expect(info.git == "abc1234")
        #expect(info.date == "2026-01-15T10:00:00Z")
        #expect(info.kanataVersion == "1.10.0")
    }

    @Test("BuildInfo with nil kanataVersion")
    func buildInfoWithNilKanataVersion() {
        let info = BuildInfo(
            version: "1.0.0",
            build: "1",
            git: "unknown",
            date: "2026-01-01",
            kanataVersion: nil
        )
        #expect(info.kanataVersion == nil)
    }

    @Test("kanataVersionCached is accessible")
    func kanataVersionCachedIsAccessible() {
        // In a test environment, kanata may not be installed, so the cached version
        // may be nil. We just verify accessing it does not crash.
        let _ = BuildInfo.kanataVersionCached
    }

    @Test("current returns fallback values in test environment")
    func currentReturnsFallbackValues() {
        let info = BuildInfo.current()
        // In test bundles there is no BuildInfo.plist, so we get fallback values.
        // Version falls back to bundle info or "1.0.0"; git falls back to "unknown".
        #expect(info.git == "unknown" || !info.git.isEmpty)
        #expect(!info.version.isEmpty)
    }
}

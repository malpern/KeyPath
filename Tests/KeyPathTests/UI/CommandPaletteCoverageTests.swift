@testable import KeyPathAppKit
import Testing

@Suite("Command Palette Coverage")
struct CommandPaletteCoverageTests {
    @Test("Every InspectorSection has a palette entry")
    @MainActor
    func allInspectorSectionsCovered() {
        let controller = CommandPaletteWindowController.shared
        let items = controller.allItemIDs()

        for section in InspectorSection.allCases {
            let expectedID = "inspector-\(section.rawValue)"
            #expect(
                items.contains(expectedID),
                "Missing command palette entry for InspectorSection.\(section.rawValue)"
            )
        }
    }

    @Test("Every SettingsTab has a palette entry")
    @MainActor
    func allSettingsTabsCovered() {
        let controller = CommandPaletteWindowController.shared
        let items = controller.allItemIDs()

        let expectedMappings: [SettingsTab: String] = [
            .status: "settings-status",
            .rules: "settings-rules",
            .general: "settings-general",
            .advanced: "settings-advanced",
        ]

        for (tab, expectedID) in expectedMappings {
            #expect(
                items.contains(expectedID),
                "Missing command palette entry for SettingsTab.\(tab)"
            )
        }
    }

    @Test("All item IDs are non-empty strings")
    @MainActor
    func allItemIDsNonEmpty() {
        let controller = CommandPaletteWindowController.shared
        let items = controller.allItemIDs()
        for id in items {
            #expect(!id.isEmpty, "Found empty item ID in command palette")
        }
    }

    @Test("Palette has navigation, collection, and settings items")
    @MainActor
    func paletteHasExpectedGroups() {
        let items = CommandPaletteWindowController.shared.allItemIDs()
        #expect(items.contains("toggle-app"), "Missing navigation item 'toggle-app'")
        #expect(items.contains(where: { $0.hasPrefix("settings-") }), "Missing settings items")
        #expect(items.contains(where: { $0.hasPrefix("inspector-") }), "Missing inspector items")
    }

    @Test("Palette has a reasonable number of items")
    @MainActor
    func paletteHasReasonableCount() {
        let items = CommandPaletteWindowController.shared.allItemIDs()
        #expect(items.count >= 10, "Palette should have at least 10 items, got \(items.count)")
        #expect(items.count < 200, "Palette has an unexpectedly large number of items: \(items.count)")
    }

    @Test("Logs settings entry exists")
    @MainActor
    func logsSettingsEntryExists() {
        let items = CommandPaletteWindowController.shared.allItemIDs()
        #expect(items.contains("settings-logs"), "Missing 'settings-logs' palette entry")
    }
}

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
}

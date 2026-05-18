import Testing
@testable import KeyPathAppKit

@Suite("OutputActionGrouping")
struct OutputActionGroupingTests {

    // MARK: - Detailed grouping (overlay mapper)

    @Test("detailed produces 5 groups in expected order")
    func detailedGroupCount() {
        let groups = OutputActionGrouping.detailed
        #expect(groups.count == 5)
        #expect(groups.map(\.title) == ["Editing", "System", "Playback", "Volume", "Display"])
    }

    @Test("detailed covers every action exactly once")
    func detailedCoversAllActions() {
        let groups = OutputActionGrouping.detailed
        let groupedIDs = groups.flatMap { $0.actions.map(\.id) }
        let allIDs = SystemActionInfo.allActions.map(\.id)

        #expect(Set(groupedIDs) == Set(allIDs), "Every action in allActions must appear in exactly one detailed group")
        #expect(groupedIDs.count == allIDs.count, "No action should appear in multiple groups")
    }

    @Test("detailed groups are non-empty")
    func detailedGroupsNonEmpty() {
        for group in OutputActionGrouping.detailed {
            #expect(!group.actions.isEmpty, "\(group.title) group should not be empty")
        }
    }

    @Test("detailed Editing group contains only editing shortcuts")
    func detailedEditingGroup() {
        let editing = OutputActionGrouping.detailed.first { $0.title == "Editing" }!
        for action in editing.actions {
            #expect(action.isEditingShortcut, "\(action.id) should be an editing shortcut")
        }
    }

    @Test("detailed System group contains only system actions")
    func detailedSystemGroup() {
        let system = OutputActionGrouping.detailed.first { $0.title == "System" }!
        for action in system.actions {
            #expect(action.isSystemAction, "\(action.id) should be a system action")
        }
    }

    @Test("detailed Playback group contains expected media keys")
    func detailedPlaybackGroup() {
        let playback = OutputActionGrouping.detailed.first { $0.title == "Playback" }!
        let ids = Set(playback.actions.map(\.id))
        #expect(ids == ["play-pause", "next-track", "prev-track"])
    }

    @Test("detailed Volume group contains expected media keys")
    func detailedVolumeGroup() {
        let volume = OutputActionGrouping.detailed.first { $0.title == "Volume" }!
        let ids = Set(volume.actions.map(\.id))
        #expect(ids == ["mute", "volume-up", "volume-down"])
    }

    @Test("detailed Display group contains expected media keys")
    func detailedDisplayGroup() {
        let display = OutputActionGrouping.detailed.first { $0.title == "Display" }!
        let ids = Set(display.actions.map(\.id))
        #expect(ids == ["brightness-up", "brightness-down"])
    }

    // MARK: - Compact grouping (chord editor)

    @Test("compact produces 3 groups in expected order")
    func compactGroupCount() {
        let groups = OutputActionGrouping.compact
        #expect(groups.count == 3)
        #expect(groups.map(\.title) == ["System", "Media", "Editing"])
    }

    @Test("compact covers every action exactly once")
    func compactCoversAllActions() {
        let groups = OutputActionGrouping.compact
        let groupedIDs = groups.flatMap { $0.actions.map(\.id) }
        let allIDs = SystemActionInfo.allActions.map(\.id)

        #expect(Set(groupedIDs) == Set(allIDs), "Every action in allActions must appear in exactly one compact group")
        #expect(groupedIDs.count == allIDs.count, "No action should appear in multiple groups")
    }

    @Test("compact groups are non-empty")
    func compactGroupsNonEmpty() {
        for group in OutputActionGrouping.compact {
            #expect(!group.actions.isEmpty, "\(group.title) group should not be empty")
        }
    }

    @Test("compact System group matches isSystemAction filter")
    func compactSystemGroup() {
        let system = OutputActionGrouping.compact.first { $0.title == "System" }!
        for action in system.actions {
            #expect(action.isSystemAction, "\(action.id) should be a system action")
        }
    }

    @Test("compact Media group matches isMediaKey filter")
    func compactMediaGroup() {
        let media = OutputActionGrouping.compact.first { $0.title == "Media" }!
        for action in media.actions {
            #expect(action.isMediaKey, "\(action.id) should be a media key")
        }
    }

    @Test("compact Editing group matches isEditingShortcut filter")
    func compactEditingGroup() {
        let editing = OutputActionGrouping.compact.first { $0.title == "Editing" }!
        for action in editing.actions {
            #expect(action.isEditingShortcut, "\(action.id) should be an editing shortcut")
        }
    }

    // MARK: - Cross-grouping consistency

    @Test("detailed and compact cover the same total set of actions")
    func bothGroupingsCoverSameActions() {
        let detailedIDs = Set(OutputActionGrouping.detailed.flatMap { $0.actions.map(\.id) })
        let compactIDs = Set(OutputActionGrouping.compact.flatMap { $0.actions.map(\.id) })
        #expect(detailedIDs == compactIDs)
    }

    @Test("detailed media subgroups union equals compact Media group")
    func detailedMediaSubgroupsMatchCompact() {
        let detailed = OutputActionGrouping.detailed
        let detailedMediaIDs = Set(
            detailed.filter { ["Playback", "Volume", "Display"].contains($0.title) }
                .flatMap { $0.actions.map(\.id) }
        )
        let compactMediaIDs = Set(
            OutputActionGrouping.compact.first { $0.title == "Media" }!.actions.map(\.id)
        )
        #expect(detailedMediaIDs == compactMediaIDs, "Playback+Volume+Display should equal Media")
    }

    // MARK: - OutputActionGroup identity

    @Test("group IDs are unique within detailed")
    func detailedGroupIDsUnique() {
        let ids = OutputActionGrouping.detailed.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("group IDs are unique within compact")
    func compactGroupIDsUnique() {
        let ids = OutputActionGrouping.compact.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Hardcoded media key IDs exist in allActions

    @Test("detailed media key IDs all exist in SystemActionInfo.allActions")
    func detailedMediaKeyIDsExist() {
        let allIDs = Set(SystemActionInfo.allActions.map(\.id))
        let hardcodedIDs: Set<String> = [
            "play-pause", "next-track", "prev-track",
            "mute", "volume-up", "volume-down",
            "brightness-up", "brightness-down",
        ]
        for id in hardcodedIDs {
            #expect(allIDs.contains(id), "\(id) must exist in SystemActionInfo.allActions")
        }
    }
}

// MARK: - KeystrokePresetGridView

@Suite("KeystrokePresetGridView")
struct KeystrokePresetGridViewTests {

    @Test("presets have unique keys")
    func presetsUnique() {
        let keys = KeystrokePresetGridView.presets.map(\.key)
        #expect(Set(keys).count == keys.count, "Preset keys must be unique")
    }

    @Test("presets are non-empty with valid fields")
    func presetsNonEmpty() {
        #expect(!KeystrokePresetGridView.presets.isEmpty)
        for preset in KeystrokePresetGridView.presets {
            #expect(!preset.key.isEmpty, "key must not be empty")
            #expect(!preset.label.isEmpty, "label must not be empty")
            #expect(!preset.icon.isEmpty, "icon must not be empty")
        }
    }

    @Test("preset count is 10")
    func presetCount() {
        #expect(KeystrokePresetGridView.presets.count == 10)
    }

    @Test("presets include expected common keys")
    func presetsIncludeCommonKeys() {
        let keys = Set(KeystrokePresetGridView.presets.map(\.key))
        let expected: Set<String> = ["esc", "enter", "bspc", "del", "tab", "spc", "up", "down", "left", "right"]
        #expect(keys == expected)
    }

    @Test("presets produce valid KeyAction values")
    func presetsProduceValidKeyActions() {
        for preset in KeystrokePresetGridView.presets {
            let action = KeyAction.keystroke(key: preset.key)
            #expect(!action.isEmpty, "\(preset.key) should produce a non-empty KeyAction")
            #expect(!action.kanataOutput.isEmpty, "\(preset.key) should produce valid kanata output")
        }
    }

    @Test("presets have display info via KeyAction.commonDisplayInfo")
    func presetsHaveDisplayInfo() {
        for preset in KeystrokePresetGridView.presets {
            let action = KeyAction.keystroke(key: preset.key)
            let info = action.commonDisplayInfo
            #expect(info != nil, "\(preset.key) should have commonDisplayInfo")
        }
    }
}

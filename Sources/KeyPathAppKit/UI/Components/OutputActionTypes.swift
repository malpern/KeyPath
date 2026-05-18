import Foundation

struct OutputActionGroup: Identifiable {
    let title: String
    let actions: [SystemActionInfo]
    var id: String { title }
}

enum OutputActionGrouping {
    static var detailed: [OutputActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            OutputActionGroup(title: "Editing", actions: all.filter(\.isEditingShortcut)),
            OutputActionGroup(title: "System", actions: all.filter(\.isSystemAction)),
            OutputActionGroup(title: "Playback", actions: all.filter {
                ["play-pause", "next-track", "prev-track"].contains($0.id)
            }),
            OutputActionGroup(title: "Volume", actions: all.filter {
                ["mute", "volume-up", "volume-down"].contains($0.id)
            }),
            OutputActionGroup(title: "Display", actions: all.filter {
                ["brightness-up", "brightness-down"].contains($0.id)
            }),
        ]
    }

    static var compact: [OutputActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            OutputActionGroup(title: "System", actions: all.filter(\.isSystemAction)),
            OutputActionGroup(title: "Media", actions: all.filter(\.isMediaKey)),
            OutputActionGroup(title: "Editing", actions: all.filter(\.isEditingShortcut)),
        ]
    }
}

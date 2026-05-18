import Foundation

struct OutputActionGroup: Identifiable {
    let title: String
    let actions: [SystemActionInfo]
    var id: String { title }
}

private let clipboardIDs: Set<String> = ["cut", "copy", "paste", "undo", "redo", "select-all", "save", "find"]
private let cursorIDs: Set<String> = ["word-left", "word-right", "line-start", "line-end"]
private let deletionIDs: Set<String> = ["delete-word", "kill-line", "forward-delete"]
private let selectionIDs: Set<String> = ["select-word-left", "select-word-right", "select-to-line-start", "select-to-line-end"]
private let tabWindowIDs: Set<String> = ["prev-tab", "next-tab", "app-switcher", "window-switcher", "close-tab"]
private let systemExtraIDs: Set<String> = ["screenshot"]

enum OutputActionGrouping {
    static var detailed: [OutputActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            OutputActionGroup(title: "Clipboard", actions: all.filter { clipboardIDs.contains($0.id) }),
            OutputActionGroup(title: "Cursor Movement", actions: all.filter { cursorIDs.contains($0.id) }),
            OutputActionGroup(title: "Selection", actions: all.filter { selectionIDs.contains($0.id) }),
            OutputActionGroup(title: "Deletion", actions: all.filter { deletionIDs.contains($0.id) }),
            OutputActionGroup(title: "Tab / Window", actions: all.filter { tabWindowIDs.contains($0.id) }),
            OutputActionGroup(title: "System", actions: all.filter { $0.isSystemAction || systemExtraIDs.contains($0.id) }),
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

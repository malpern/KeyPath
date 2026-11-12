import Foundation
import KeyPathRulesCore

struct OutputActionGroup: Identifiable {
    let title: String
    let actions: [SystemActionInfo]
    var id: String {
        title
    }
}

private let clipboardIDs: Set<String> = ["cut", "copy", "paste", "undo", "redo", "select-all", "save", "find"]
private let cursorIDs: Set<String> = ["word-left", "word-right", "line-start", "line-end"]
private let deletionIDs: Set<String> = ["delete-word", "kill-line", "forward-delete"]
private let selectionIDs: Set<String> = ["select-word-left", "select-word-right", "select-to-line-start", "select-to-line-end"]
private let tabWindowIDs: Set<String> = ["prev-tab", "next-tab", "app-switcher", "window-switcher", "close-tab"]
private let systemExtraIDs: Set<String> = ["screenshot"]
private let mediaIDs: Set<String> = [
    "play-pause", "next-track", "prev-track",
    "mute", "volume-up", "volume-down",
    "brightness-up", "brightness-down",
]
private let editingIDs: Set<String> = clipboardIDs
    .union(cursorIDs)
    .union(selectionIDs)
    .union(deletionIDs)
    .union(tabWindowIDs)

enum OutputActionGrouping {
    static var detailed: [OutputActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            OutputActionGroup(title: String(localized: "Clipboard"), actions: all.filter { clipboardIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Cursor Movement"), actions: all.filter { cursorIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Selection"), actions: all.filter { selectionIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Deletion"), actions: all.filter { deletionIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Tab / Window"), actions: all.filter { tabWindowIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "System"), actions: all.filter { $0.isSystemAction || systemExtraIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Playback"), actions: all.filter { mediaIDs.contains($0.id) && ["play-pause", "next-track", "prev-track"].contains($0.id) }),
            OutputActionGroup(title: String(localized: "Volume"), actions: all.filter { ["mute", "volume-up", "volume-down"].contains($0.id) }),
            OutputActionGroup(title: String(localized: "Display"), actions: all.filter { ["brightness-up", "brightness-down"].contains($0.id) }),
        ]
    }

    static var compact: [OutputActionGroup] {
        let all = SystemActionInfo.allActions
        return [
            OutputActionGroup(title: String(localized: "System"), actions: all.filter { $0.isSystemAction || systemExtraIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Media"), actions: all.filter { mediaIDs.contains($0.id) }),
            OutputActionGroup(title: String(localized: "Editing"), actions: all.filter { editingIDs.contains($0.id) }),
        ]
    }
}

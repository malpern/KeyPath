import SwiftUI

// MARK: - Helpers

extension PackDetailView {
    func displayLabel(for kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        case "caps": "\u{21EA}"
        case "lmet": "\u{2318}"
        case "rmet": "\u{2318}"
        case "lalt": "\u{2325}"
        case "ralt": "\u{2325}"
        case "lctl": "\u{2303}"
        case "rctl": "\u{2303}"
        case "lsft": "\u{21E7}"
        case "rsft": "\u{21E7}"
        case "spc": "Space"
        case "ret", "enter": "\u{23CE}"
        case "tab": "\u{21E5}"
        case "esc": "\u{238B}"
        case "bspc", "backspace": "\u{232B}"
        case "del": "\u{2326}"
        case "minus": "-"
        case "equal": "="
        default: kanataKey
        }
    }

    /// Dismiss this sheet and bring the Gallery window forward. Works
    /// whether Pack Detail was opened from the Gallery itself (no-op
    /// beyond dismiss) or from another surface like the Suggested banner.
    func openGalleryWindow() {
        dismiss()
        GalleryWindowController.shared.showWindow(kanataManager: kanataManager)
    }

    func loadDefaultQuickSettings() {
        for setting in pack.quickSettings {
            if quickSettingValues[setting.id] == nil,
               let defaultVal = setting.defaultSliderValue
            {
                quickSettingValues[setting.id] = defaultVal
            }
        }
    }

    func sliderBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { Double(quickSettingValues[id] ?? 0) },
            set: { quickSettingValues[id] = Int($0) }
        )
    }

    func copyValidationErrorsToClipboard() {
        // Placeholder for future implementation
    }
}

// MARK: - Undo snapshot

struct UndoSnapshot {
    let quickSettingValues: [String: Int]
}

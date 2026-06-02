import SwiftUI

// MARK: - Helpers

extension PackDetailView {
    func debouncedRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await refreshInstallState()
        }
    }

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

    var holdTimingDefaultValue: Int {
        holdTimingQuickSetting?.defaultSliderValue ?? 180
    }

    var holdTimingQuickSetting: PackQuickSetting? {
        pack.quickSettings.first { $0.id == "holdTimeout" }
    }

    var holdTimingQuickSettingRange: ClosedRange<Double> {
        if case let .slider(_, min: lo, max: hi, step: _, unitSuffix: _) = holdTimingQuickSetting?.kind {
            return Double(lo) ... Double(hi)
        }
        return 120 ... 300
    }

    var holdTimingQuickSettingStep: Double {
        if case let .slider(_, min: _, max: _, step: step, unitSuffix: _) = holdTimingQuickSetting?.kind {
            return Double(step)
        }
        return 20
    }
}

// MARK: - Undo snapshot

struct UndoSnapshot {
    let quickSettingValues: [String: Int]
}

import Foundation
import Observation

@Observable
@MainActor
final class LayoutTracerMenuState {
    static let shared = LayoutTracerMenuState()

    var canSave = false
    var canUndo = false
    var canRedo = false
    var canClearGuides = false
    var snapEnabled = true
    var showsSnapGuides = true

    var save: (() -> Void)?
    var saveAs: (() -> Void)?
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    var clearGuides: (() -> Void)?
    var setSnapEnabled: ((Bool) -> Void)?
    var setShowsSnapGuides: ((Bool) -> Void)?

    private init() {}
}

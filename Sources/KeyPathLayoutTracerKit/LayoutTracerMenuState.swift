import Foundation

@MainActor
final class LayoutTracerMenuState: ObservableObject {
    static let shared = LayoutTracerMenuState()

    @Published var canSave = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var canClearGuides = false
    @Published var snapEnabled = true
    @Published var showsSnapGuides = true

    var save: (() -> Void)?
    var saveAs: (() -> Void)?
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    var clearGuides: (() -> Void)?
    var setSnapEnabled: ((Bool) -> Void)?
    var setShowsSnapGuides: ((Bool) -> Void)?

    private init() {}
}

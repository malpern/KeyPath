import SwiftUI

struct LayoutTracerMenuCommands: Commands {
    @ObservedObject var menuState: LayoutTracerMenuState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                menuState.save?()
            }
            .disabled(!menuState.canSave)
            .keyboardShortcut("s")

            Button("Save As…") {
                menuState.saveAs?()
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                menuState.undo?()
            }
            .disabled(!menuState.canUndo)
            .keyboardShortcut("z")

            Button("Redo") {
                menuState.redo?()
            }
            .disabled(!menuState.canRedo)
            .keyboardShortcut("Z", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Toggle("Snap to Nearby Keys", isOn: Binding(
                get: { menuState.snapEnabled },
                set: { menuState.setSnapEnabled?($0) }
            ))

            Toggle("Show Snap Guides", isOn: Binding(
                get: { menuState.showsSnapGuides },
                set: { menuState.setShowsSnapGuides?($0) }
            ))

            Divider()

            Button("Clear Guides") {
                menuState.clearGuides?()
            }
            .disabled(!menuState.canClearGuides)
        }
    }
}

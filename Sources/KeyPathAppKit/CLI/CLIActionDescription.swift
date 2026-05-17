import Foundation

// MARK: - CLI–GUI Parity Guard
// Exhaustive switches on KeyAction and MappingBehavior ensure the CLI won't
// compile if a new case is added without CLI support.

public extension KeyAction {
    var cliSchemaName: String {
        switch self {
        case .keystroke: "key"
        case .hyper: "hyper"
        case .meh: "meh"
        case .launchApp: "launch-app"
        case .openURL: "open-url"
        case .openFolder: "open-folder"
        case .runScript: "run-script"
        case .systemAction: "system-action"
        case .notify: "notify"
        case .windowAction: "window"
        case .fakeKey: "fake-key"
        case .activateLayer: "activate-layer"
        case .rawKanata: "raw-kanata"
        }
    }

    var cliSchemaDescription: String {
        switch self {
        case .keystroke: "Emit a different key (simple remap)"
        case .hyper: "Hyper modifier combo (Cmd+Ctrl+Alt+Shift)"
        case .meh: "Meh modifier combo (Ctrl+Alt+Shift)"
        case .launchApp: "Launch an application by name or bundle ID"
        case .openURL: "Open a URL in the default browser"
        case .openFolder: "Open a folder in Finder"
        case .runScript: "Run a script file"
        case .systemAction: "Trigger a system action (volume, brightness, etc.)"
        case .notify: "Show a user notification"
        case .windowAction: "Window management action (left half, maximize, etc.)"
        case .fakeKey: "Trigger a Kanata virtual/fake key"
        case .activateLayer: "Switch to or activate a layer"
        case .rawKanata: "Raw kanata expression (power user escape hatch)"
        }
    }

    static var allSchemaDescriptions: [CLISchemaEntry] {
        let representative: [KeyAction] = [
            .keystroke(key: ""), .hyper, .meh,
            .launchApp(name: "", bundleId: nil), .openURL(""), .openFolder(path: "", name: nil),
            .runScript(path: "", name: nil), .systemAction(id: ""), .notify(title: "", body: nil, sound: false),
            .windowAction(position: ""), .fakeKey(name: "", action: .tap), .activateLayer(name: ""),
            .rawKanata(""),
        ]
        return representative.map { CLISchemaEntry(name: $0.cliSchemaName, description: $0.cliSchemaDescription) }
    }
}

public extension MappingBehavior {
    var cliSchemaName: String {
        switch self {
        case .dualRole: "tap-hold"
        case .tapOrTapDance: "tap-dance"
        case .macro: "macro"
        case .chord: "chord"
        }
    }

    var cliSchemaDescription: String {
        switch self {
        case .dualRole: "Dual-role key: tap produces one action, hold produces another"
        case .tapOrTapDance: "Tap behavior with optional multi-tap (tap-dance)"
        case .macro: "Macro: one trigger key produces multiple outputs or text"
        case .chord: "Chord: multiple keys pressed together produce a single output"
        }
    }

    static var allSchemaDescriptions: [CLISchemaEntry] {
        let representative: [MappingBehavior] = [
            .dualRole(DualRoleBehavior(tapAction: .empty, holdAction: .empty)),
            .tapOrTapDance(.tap),
            .macro(MacroBehavior()),
            .chord(ChordBehavior(keys: [], output: .empty)),
        ]
        return representative.map { CLISchemaEntry(name: $0.cliSchemaName, description: $0.cliSchemaDescription) }
    }
}

public struct CLISchemaEntry: Codable, Sendable {
    public let name: String
    public let description: String
}

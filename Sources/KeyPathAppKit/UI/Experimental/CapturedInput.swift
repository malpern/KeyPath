import AppKit
import SwiftUI

// MARK: - Data Models

enum CapturedInput: Identifiable, Equatable {
    case key(KeyInput)
    case app(AppInput)
    case url(URLInput)

    var id: String {
        switch self {
        case let .key(k): "key-\(k.id)"
        case let .app(a): "app-\(a.id)"
        case let .url(u): "url-\(u.id)"
        }
    }

    struct KeyInput: Identifiable, Equatable {
        let id = UUID()
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags

        var displayName: String {
            characters.uppercased()
        }

        var isModifier: Bool {
            ["⌘", "⇧", "⌥", "⌃", "fn"].contains(characters)
        }
    }

    struct AppInput: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let bundleIdentifier: String
        let icon: NSImage?
    }

    struct URLInput: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
    }
}

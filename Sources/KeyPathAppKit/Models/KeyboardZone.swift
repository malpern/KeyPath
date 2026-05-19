import SwiftUI

#if os(macOS)
    import AppKit
#endif

enum KeyboardZone: Equatable, Sendable {
    case modifier
    case activator
    case navMapping
    case dimmed

    var color: Color {
        switch self {
        case .modifier: Color.blue.opacity(0.45)
        case .activator: Color.orange.opacity(0.5)
        case .navMapping: Color.green.opacity(0.45)
        case .dimmed: Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    var borderColor: Color {
        switch self {
        case .modifier: Color.blue.opacity(0.7)
        case .activator: Color.orange.opacity(0.8)
        case .navMapping: Color.green.opacity(0.7)
        case .dimmed: Color.secondary.opacity(0.1)
        }
    }
}

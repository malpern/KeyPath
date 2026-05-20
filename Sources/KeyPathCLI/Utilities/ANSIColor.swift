import Foundation

enum ANSIColor {
    static func green(_ s: String, noColor: Bool) -> String {
        noColor ? s : "\u{001b}[32m\(s)\u{001b}[0m"
    }

    static func red(_ s: String, noColor: Bool) -> String {
        noColor ? s : "\u{001b}[31m\(s)\u{001b}[0m"
    }

    static func yellow(_ s: String, noColor: Bool) -> String {
        noColor ? s : "\u{001b}[33m\(s)\u{001b}[0m"
    }

    static func dim(_ s: String, noColor: Bool) -> String {
        noColor ? s : "\u{001b}[2m\(s)\u{001b}[0m"
    }

    static func bold(_ s: String, noColor: Bool) -> String {
        noColor ? s : "\u{001b}[1m\(s)\u{001b}[0m"
    }
}

import Foundation

enum KeyPathMessageType: Codable {
    case text(String)
    case rule(KanataRule)
}

struct KeyPathMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    let type: KeyPathMessageType
    let timestamp: Date
    
    init(role: ChatRole, text: String) {
        self.role = role
        self.type = .text(text)
        self.timestamp = Date()
    }
    
    init(role: ChatRole, rule: KanataRule) {
        self.role = role
        self.type = .rule(rule)
        self.timestamp = Date()
    }
    
    var displayText: String {
        switch type {
        case .text(let text):
            return text
        case .rule(let rule):
            return rule.explanation
        }
    }
    
    var isRule: Bool {
        if case .rule = type {
            return true
        }
        return false
    }
    
    var rule: KanataRule? {
        if case .rule(let rule) = type {
            return rule
        }
        return nil
    }
    
    static func == (lhs: KeyPathMessage, rhs: KeyPathMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

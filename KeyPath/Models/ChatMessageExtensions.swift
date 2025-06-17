import Foundation

enum ChatMessageType {
    case text
    case rule(KanataRule)
}

extension ChatMessage {
    var messageType: ChatMessageType {
        if let rule = associatedRule {
            return .rule(rule)
        } else {
            return .text
        }
    }
    
    // Store the rule if this message contains one
    var associatedRule: KanataRule? {
        get {
            // Try to decode from userInfo if we add that capability
            return nil
        }
    }
}

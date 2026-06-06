import Foundation

enum UserFeedbackService {
    static func show(message: String) {
        NotificationCenter.default.post(
            name: .showUserFeedback,
            object: nil,
            userInfo: ["message": message]
        )
    }
}

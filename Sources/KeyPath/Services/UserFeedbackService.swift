import Foundation

enum UserFeedbackService {
    static func show(message: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowUserFeedback"),
            object: nil,
            userInfo: ["message": message]
        )
    }
}



import Foundation
import AppKit

class SoundManager {
    static let shared = SoundManager()

    private init() {}

    enum SoundType {
        case success
        case deactivation

        var fileName: String {
            switch self {
            case .success:
                return "Ping"
            case .deactivation:
                return "Pop"
            }
        }
    }

    func playSound(_ type: SoundType) {
        let soundPath = "/System/Library/Sounds/\(type.fileName).aiff"
        let soundURL = URL(fileURLWithPath: soundPath)

        guard FileManager.default.fileExists(atPath: soundPath) else {
            print("Sound file not found: \(soundPath)")
            return
        }

        // Use NSSound for simple system sound playback
        if let sound = NSSound(contentsOf: soundURL, byReference: true) {
            sound.play()
        } else {
            print("Failed to create NSSound from: \(soundPath)")
        }
    }
}

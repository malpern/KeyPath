import Foundation
import AppKit

/// Manager for system sounds to provide audio feedback
class SoundManager {
    static let shared = SoundManager()
    
    private init() {}
    
    /// Play tink sound when saving configuration
    func playTinkSound() {
        NSSound(named: "Tink")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing tink sound for config save")
    }
    
    /// Play glass sound when configuration reload is complete
    func playGlassSound() {
        NSSound(named: "Glass")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing glass sound for reload complete")
    }
    
    /// Play system beep for errors
    func playErrorSound() {
        NSSound.beep()
        AppLogger.shared.log("🔊 [Sound] Playing error beep")
    }
    
    /// Play submarine sound for successful operations (alternative to glass)
    func playSubmarineSound() {
        NSSound(named: "Submarine")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing submarine sound for success")
    }
}
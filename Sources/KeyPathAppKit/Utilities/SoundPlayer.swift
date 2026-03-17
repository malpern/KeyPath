import AppKit
import Foundation
import KeyPathCore

@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var successSound: NSSound?
    private var errorSound: NSSound?
    private var deviceConnectedSound: NSSound?
    private var deviceDisconnectedSound: NSSound?

    private init() {
        setupSounds()
    }

    private func setupSounds() {
        // Use system sounds - these are always available
        successSound = NSSound(named: "Glass")
        errorSound = NSSound(named: "Basso")
        deviceConnectedSound = NSSound(named: "Funk")
        deviceDisconnectedSound = NSSound(named: "Bottle")

        AppLogger.shared.log(
            "🔊 [SoundPlayer] Initialized with Glass (success), Basso (error), Funk (connect), Bottle (disconnect) sounds"
        )
    }

    /// Play success sound (glass sound for config reload success)
    func playSuccessSound() {
        guard let sound = successSound else {
            AppLogger.shared.log("⚠️ [SoundPlayer] Success sound not available")
            return
        }

        // Already on @MainActor; play directly
        sound.play()
        AppLogger.shared.log("🔊 [SoundPlayer] Playing success sound (Glass)")
    }

    /// Play error sound (basso sound for config reload failure)
    func playErrorSound() {
        guard let sound = errorSound else {
            AppLogger.shared.log("⚠️ [SoundPlayer] Error sound not available")
            return
        }

        // Already on @MainActor; play directly
        sound.play()
        AppLogger.shared.log("🔊 [SoundPlayer] Playing error sound (Basso)")
    }

    /// Play sound when a keyboard is detected/connected
    func playDeviceConnectedSound() {
        deviceConnectedSound?.play()
    }

    /// Play sound when a keyboard is disconnected
    func playDeviceDisconnectedSound() {
        deviceDisconnectedSound?.play()
    }

    /// Test if sounds are available
    func testSounds() {
        AppLogger.shared.log("🔊 [SoundPlayer] Testing sounds...")
        playSuccessSound()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.playErrorSound()
        }
    }
}

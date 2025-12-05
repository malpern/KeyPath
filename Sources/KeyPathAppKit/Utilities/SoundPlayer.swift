import AppKit
import Foundation
import KeyPathCore

@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private var successSound: NSSound?
    private var errorSound: NSSound?

    private init() {
        setupSounds()
    }

    private func setupSounds() {
        // Use system sounds for now - these are always available
        successSound = NSSound(named: "Glass")
        errorSound = NSSound(named: "Basso")

        AppLogger.shared.log(
            "🔊 [SoundPlayer] Initialized with Glass (success) and Basso (error) sounds")
    }

    /// Play success sound (glass sound for config reload success)
    func playSuccessSound() {
        guard let sound = successSound else {
            AppLogger.shared.log("⚠️ [SoundPlayer] Success sound not available")
            return
        }

        sound.play()
        AppLogger.shared.log("🔊 [SoundPlayer] Playing success sound (Glass)")
    }

    /// Play error sound (basso sound for config reload failure)
    func playErrorSound() {
        guard let sound = errorSound else {
            AppLogger.shared.log("⚠️ [SoundPlayer] Error sound not available")
            return
        }

        sound.play()
        AppLogger.shared.log("🔊 [SoundPlayer] Playing error sound (Basso)")
    }

    /// Test if sounds are available
    func testSounds() {
        AppLogger.shared.log("🔊 [SoundPlayer] Testing sounds...")
        playSuccessSound()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.playErrorSound()
        }
    }
}

import AppKit
import Foundation
import KeyPathCore

/// Manager for system sounds to provide audio feedback
@MainActor
class SoundManager {
    static let shared = SoundManager()

    private init() {}

    /// Gate that silences every sound when:
    /// * We're running inside XCTest (pre-existing behavior), OR
    /// * The frontmost app's bundle identifier is on the user's
    ///   `overlaySuppressedBundleIDs` list (Settings → Experimental).
    private func shouldSuppress() -> Bool {
        if TestEnvironment.isRunningTests { return true }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           PreferencesService.shared.overlaySuppressedBundleIDs.contains(front)
        {
            return true
        }
        return false
    }

    /// Play tink sound when saving configuration
    func playTinkSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed tink sound")
            return
        }
        NSSound(named: "Tink")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing tink sound for config save")
    }

    /// Play glass sound when configuration reload is complete
    func playGlassSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed glass sound")
            return
        }
        NSSound(named: "Glass")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing glass sound for reload complete")
    }

    /// Play system beep for errors
    func playErrorSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed error beep")
            return
        }
        NSSound.beep()
        AppLogger.shared.log("🔊 [Sound] Playing error beep")
    }

    /// Play warning sound for conflicts (non-blocking warnings)
    func playWarningSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed warning sound")
            return
        }
        // "Basso" is a low, cautionary sound - appropriate for warnings
        playSubtleSound(named: "Basso", volume: 0.4)
        AppLogger.shared.log("🔊 [Sound] Playing warning sound (Basso) for conflict")
    }

    /// Play submarine sound for successful operations (alternative to glass)
    func playSubmarineSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed submarine sound")
            return
        }
        NSSound(named: "Submarine")?.play()
        AppLogger.shared.log("🔊 [Sound] Playing submarine sound for success")
    }

    // MARK: - Layer Change Sounds

    /// Play subtle sound when entering a non-base layer (higher pitch)
    func playLayerUpSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed layer-up sound")
            return
        }
        // "Tink" is a light, higher-pitched tap - good for going "up"
        playSubtleSound(named: "Tink", volume: 0.3)
        AppLogger.shared.log("🔊 [Sound] Playing layer-up sound (Tink)")
    }

    /// Play subtle sound when returning to base layer (lower pitch)
    func playLayerDownSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed layer-down sound")
            return
        }
        // "Pop" has a lower, softer quality - good for settling "down"
        playSubtleSound(named: "Pop", volume: 0.2)
        AppLogger.shared.log("🔊 [Sound] Playing layer-down sound (Pop)")
    }

    // MARK: - Overlay Sounds

    /// Play subtle sound when overlay appears
    func playOverlayShowSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed overlay-show sound")
            return
        }
        // "Bottle" is a soft cork/bubble sound - gentle for appearing
        playSubtleSound(named: "Bottle", volume: 0.075)
        AppLogger.shared.log("🔊 [Sound] Playing overlay-show sound (Bottle)")
    }

    /// Play subtle sound when overlay hides
    func playOverlayHideSound() {
        if shouldSuppress() {
            AppLogger.shared.log("🔇 [Sound] Suppressed overlay-hide sound")
            return
        }
        // "Funk" is a subtle descending tone - good for dismissing
        playSubtleSound(named: "Funk", volume: 0.06)
        AppLogger.shared.log("🔊 [Sound] Playing overlay-hide sound (Funk)")
    }

    /// Play a system sound at reduced volume for subtle feedback
    private func playSubtleSound(named name: String, volume: Float) {
        guard let sound = NSSound(named: name) else {
            AppLogger.shared.log("⚠️ [Sound] Sound '\(name)' not found")
            return
        }
        sound.volume = volume
        sound.play()
    }
}

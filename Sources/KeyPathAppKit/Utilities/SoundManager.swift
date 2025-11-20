import AppKit
import Foundation
import KeyPathCore

/// Manager for system sounds to provide audio feedback
@MainActor
class SoundManager {
  static let shared = SoundManager()

  private init() {}

  /// Play tink sound when saving configuration
  func playTinkSound() {
    if TestEnvironment.isRunningTests {
      AppLogger.shared.log("🧪 [Sound] Suppressed tink sound in test environment")
      return
    }
    NSSound(named: "Tink")?.play()
    AppLogger.shared.log("🔊 [Sound] Playing tink sound for config save")
  }

  /// Play glass sound when configuration reload is complete
  func playGlassSound() {
    if TestEnvironment.isRunningTests {
      AppLogger.shared.log("🧪 [Sound] Suppressed glass sound in test environment")
      return
    }
    NSSound(named: "Glass")?.play()
    AppLogger.shared.log("🔊 [Sound] Playing glass sound for reload complete")
  }

  /// Play system beep for errors
  func playErrorSound() {
    if TestEnvironment.isRunningTests {
      AppLogger.shared.log("🧪 [Sound] Suppressed error beep in test environment")
      return
    }
    NSSound.beep()
    AppLogger.shared.log("🔊 [Sound] Playing error beep")
  }

  /// Play submarine sound for successful operations (alternative to glass)
  func playSubmarineSound() {
    if TestEnvironment.isRunningTests {
      AppLogger.shared.log("🧪 [Sound] Suppressed submarine sound in test environment")
      return
    }
    NSSound(named: "Submarine")?.play()
    AppLogger.shared.log("🔊 [Sound] Playing submarine sound for success")
  }
}

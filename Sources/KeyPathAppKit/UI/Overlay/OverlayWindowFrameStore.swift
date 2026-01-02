import CoreGraphics
import Foundation

struct OverlayWindowFrameStore {
    static let currentFrameVersion = 6

    private enum Keys {
        static let windowX = "LiveKeyboardOverlay.windowX"
        static let windowY = "LiveKeyboardOverlay.windowY"
        static let windowWidth = "LiveKeyboardOverlay.windowWidth"
        static let windowHeight = "LiveKeyboardOverlay.windowHeight"
        static let frameVersion = "LiveKeyboardOverlay.frameVersion"
    }

    let defaults: UserDefaults
    let frameVersion: Int

    init(
        defaults: UserDefaults = .standard,
        frameVersion: Int = OverlayWindowFrameStore.currentFrameVersion
    ) {
        self.defaults = defaults
        self.frameVersion = frameVersion
    }

    func save(frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        defaults.set(frame.origin.x, forKey: Keys.windowX)
        defaults.set(frame.origin.y, forKey: Keys.windowY)
        defaults.set(frame.size.width, forKey: Keys.windowWidth)
        defaults.set(frame.size.height, forKey: Keys.windowHeight)
        defaults.set(frameVersion, forKey: Keys.frameVersion)
    }

    func clear() {
        defaults.removeObject(forKey: Keys.windowWidth)
        defaults.removeObject(forKey: Keys.windowHeight)
        defaults.removeObject(forKey: Keys.windowX)
        defaults.removeObject(forKey: Keys.windowY)
        defaults.set(frameVersion, forKey: Keys.frameVersion)
    }

    func restore() -> CGRect? {
        let savedVersion = defaults.integer(forKey: Keys.frameVersion)
        if savedVersion < frameVersion {
            clear()
            return nil
        }

        let width = defaults.double(forKey: Keys.windowWidth)
        guard width > 0 else { return nil }

        let x = defaults.double(forKey: Keys.windowX)
        let y = defaults.double(forKey: Keys.windowY)
        let height = defaults.double(forKey: Keys.windowHeight)
        guard height > 0 else {
            clear()
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

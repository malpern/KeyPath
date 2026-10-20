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
        static let framesByDisplay = "LiveKeyboardOverlay.framesByDisplay"
        static let lastVisibleFrame = "LiveKeyboardOverlay.lastVisibleFrame"
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

    /// Remembers the frame for one display, plus that display's usable area so the
    /// frame can be carried to a display it has never been on at the same relative spot.
    func save(frame: CGRect, displayKey: String, visibleFrame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        save(frame: frame)
        var byDisplay = defaults.dictionary(forKey: Keys.framesByDisplay) as? [String: [Double]] ?? [:]
        byDisplay[displayKey] = Self.encode(frame)
        defaults.set(byDisplay, forKey: Keys.framesByDisplay)
        defaults.set(Self.encode(visibleFrame), forKey: Keys.lastVisibleFrame)
    }

    func frame(forDisplay displayKey: String) -> CGRect? {
        guard defaults.integer(forKey: Keys.frameVersion) >= frameVersion else { return nil }
        let byDisplay = defaults.dictionary(forKey: Keys.framesByDisplay) as? [String: [Double]]
        return byDisplay?[displayKey].flatMap(Self.decode)
    }

    func lastVisibleFrame() -> CGRect? {
        (defaults.array(forKey: Keys.lastVisibleFrame) as? [Double]).flatMap(Self.decode)
    }

    private static func encode(_ rect: CGRect) -> [Double] {
        [rect.origin.x, rect.origin.y, rect.width, rect.height]
    }

    private static func decode(_ values: [Double]) -> CGRect? {
        guard values.count == 4, values[2] > 0, values[3] > 0 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func clear() {
        defaults.removeObject(forKey: Keys.framesByDisplay)
        defaults.removeObject(forKey: Keys.lastVisibleFrame)
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

import Foundation

// MARK: - Geometry

struct KeyboardStagePoint: Equatable, Sendable {
    var x: Float
    var y: Float

    static let zero = KeyboardStagePoint(x: 0, y: 0)

    static func interpolated(
        from start: KeyboardStagePoint,
        to end: KeyboardStagePoint,
        progress: Float
    ) -> KeyboardStagePoint {
        KeyboardStagePoint(
            x: interpolate(start.x, end.x, progress),
            y: interpolate(start.y, end.y, progress)
        )
    }
}

struct KeyboardStageSize: Equatable, Sendable {
    var width: Float
    var height: Float

    static let zero = KeyboardStageSize(width: 0, height: 0)

    static func interpolated(
        from start: KeyboardStageSize,
        to end: KeyboardStageSize,
        progress: Float
    ) -> KeyboardStageSize {
        KeyboardStageSize(
            width: interpolate(start.width, end.width, progress),
            height: interpolate(start.height, end.height, progress)
        )
    }
}

struct KeyboardStageRect: Equatable, Sendable {
    var origin: KeyboardStagePoint
    var size: KeyboardStageSize

    init(x: Float, y: Float, width: Float, height: Float) {
        origin = KeyboardStagePoint(x: x, y: y)
        size = KeyboardStageSize(width: width, height: height)
    }

    init(origin: KeyboardStagePoint, size: KeyboardStageSize) {
        self.origin = origin
        self.size = size
    }

    var minX: Float {
        origin.x
    }

    var minY: Float {
        origin.y
    }

    var maxX: Float {
        origin.x + size.width
    }

    var maxY: Float {
        origin.y + size.height
    }

    var midX: Float {
        origin.x + size.width / 2
    }

    var midY: Float {
        origin.y + size.height / 2
    }

    var center: KeyboardStagePoint {
        KeyboardStagePoint(x: midX, y: midY)
    }

    func insetBy(dx: Float, dy: Float) -> KeyboardStageRect {
        KeyboardStageRect(
            x: origin.x + dx,
            y: origin.y + dy,
            width: max(0, size.width - 2 * dx),
            height: max(0, size.height - 2 * dy)
        )
    }

    func union(_ other: KeyboardStageRect) -> KeyboardStageRect {
        let x = min(minX, other.minX)
        let y = min(minY, other.minY)
        return KeyboardStageRect(
            x: x,
            y: y,
            width: max(maxX, other.maxX) - x,
            height: max(maxY, other.maxY) - y
        )
    }

    static func interpolated(
        from start: KeyboardStageRect,
        to end: KeyboardStageRect,
        progress: Float
    ) -> KeyboardStageRect {
        KeyboardStageRect(
            origin: .interpolated(from: start.origin, to: end.origin, progress: progress),
            size: .interpolated(from: start.size, to: end.size, progress: progress)
        )
    }
}

private func interpolate(_ start: Float, _ end: Float, _ progress: Float) -> Float {
    start + (end - start) * progress
}

// MARK: - Display and semantics

struct KeyboardStageDisplayMode: Equatable, Sendable {
    enum Appearance: Equatable, Sendable {
        case light
        case dark
    }

    var appearance: Appearance
    var reduceMotion: Bool
    var increaseContrast: Bool
    var reduceTransparency: Bool
    var differentiateWithoutColor: Bool

    init(
        appearance: Appearance = .light,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        differentiateWithoutColor: Bool = false
    ) {
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    static let standard = KeyboardStageDisplayMode(
        appearance: .light,
        reduceMotion: false,
        reduceTransparency: false,
        increaseContrast: false,
        differentiateWithoutColor: false
    )
}

enum KeyboardStageKeyRole: Equatable, Sendable {
    case deck
    case standard
    case modifier
    case recommended
    case escape
    case hyper
    case launcher
    case installed
    case dimmed
}

struct KeyboardStageApplicationTarget: Equatable, Sendable {
    var name: String
    var bundleIdentifier: String?
    var fallbackSystemImage: String

    init(
        name: String,
        bundleIdentifier: String? = nil,
        fallbackSystemImage: String = "app.fill"
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.fallbackSystemImage = fallbackSystemImage
    }
}

enum KeyboardStageAccessibilityRole: Equatable, Sendable {
    case capsToEscape
    case capsToHyper
    case launcherKey(letter: String, application: KeyboardStageApplicationTarget)
}

enum KeyboardStageRevealTarget: Equatable, Sendable {
    case none
    case capsToEscape(keyID: String)
    case capsToHyper(keyID: String)
    case application(keyID: String, application: KeyboardStageApplicationTarget)
    case launcherChoice
    case rules
}

// MARK: - Scene elements

struct KeyboardStageLegend: Equatable, Sendable {
    var primary: String
    var previous: String?
    var secondary: String?
    var transitionProgress: Float

    init(
        primary: String,
        previous: String? = nil,
        secondary: String? = nil,
        transitionProgress: Float = 1
    ) {
        self.primary = primary
        self.previous = previous
        self.secondary = secondary
        self.transitionProgress = transitionProgress
    }

    static func interpolated(
        from start: KeyboardStageLegend,
        to end: KeyboardStageLegend,
        progress: Float
    ) -> KeyboardStageLegend {
        if start.primary != end.primary {
            return KeyboardStageLegend(
                primary: end.primary,
                previous: start.primary,
                secondary: progress < 0.5 ? start.secondary : end.secondary,
                transitionProgress: progress
            )
        }

        return KeyboardStageLegend(
            primary: end.primary,
            previous: end.previous ?? start.previous,
            secondary: progress < 0.5 ? start.secondary : end.secondary,
            transitionProgress: interpolate(
                start.transitionProgress,
                end.transitionProgress,
                progress
            )
        )
    }
}

struct KeyboardStageKey: Identifiable, Equatable, Sendable {
    let id: String
    let keyCode: UInt16
    var frame: KeyboardStageRect
    var rotationRadians: Float
    var legend: KeyboardStageLegend
    var role: KeyboardStageKeyRole
    var opacity: Float
    var pressure: Float
    var glow: Float
    var scale: Float
    var translation: KeyboardStagePoint
    var accessibilityRole: KeyboardStageAccessibilityRole?

    var transformedFrame: KeyboardStageRect {
        let width = frame.size.width * scale
        let height = frame.size.height * scale
        return KeyboardStageRect(
            x: frame.midX - width / 2 + translation.x,
            y: frame.midY - height / 2 + translation.y,
            width: width,
            height: height
        )
    }

    fileprivate func fadedOut() -> KeyboardStageKey {
        var copy = self
        copy.opacity = 0
        copy.glow = 0
        return copy
    }

    fileprivate static func interpolated(
        from start: KeyboardStageKey,
        to end: KeyboardStageKey,
        progress: Float
    ) -> KeyboardStageKey {
        KeyboardStageKey(
            id: end.id,
            keyCode: end.keyCode,
            frame: .interpolated(from: start.frame, to: end.frame, progress: progress),
            rotationRadians: interpolate(start.rotationRadians, end.rotationRadians, progress),
            legend: .interpolated(from: start.legend, to: end.legend, progress: progress),
            role: progress < 0.5 ? start.role : end.role,
            opacity: interpolate(start.opacity, end.opacity, progress),
            pressure: interpolate(start.pressure, end.pressure, progress),
            glow: interpolate(start.glow, end.glow, progress),
            scale: interpolate(start.scale, end.scale, progress),
            translation: .interpolated(
                from: start.translation,
                to: end.translation,
                progress: progress
            ),
            accessibilityRole: progress < 0.5 ? start.accessibilityRole : end.accessibilityRole
        )
    }
}

struct KeyboardStageDecoration: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keyboardDeck
        case capsEcho(label: String)
        case modifierToken(symbol: String)
        case launcherCandidateMarker(keyID: String)
        case applicationTarget(KeyboardStageApplicationTarget)
        case launcherChoiceTarget
        case handoffTarget
    }

    let id: String
    var kind: Kind
    var frame: KeyboardStageRect
    var rotationRadians: Float
    var role: KeyboardStageKeyRole
    var opacity: Float
    var pressure: Float
    var glow: Float
    var scale: Float

    fileprivate func fadedOut() -> KeyboardStageDecoration {
        var copy = self
        copy.opacity = 0
        copy.glow = 0
        return copy
    }

    fileprivate static func interpolated(
        from start: KeyboardStageDecoration,
        to end: KeyboardStageDecoration,
        progress: Float
    ) -> KeyboardStageDecoration {
        KeyboardStageDecoration(
            id: end.id,
            kind: progress < 0.5 ? start.kind : end.kind,
            frame: .interpolated(from: start.frame, to: end.frame, progress: progress),
            rotationRadians: interpolate(start.rotationRadians, end.rotationRadians, progress),
            role: progress < 0.5 ? start.role : end.role,
            opacity: interpolate(start.opacity, end.opacity, progress),
            pressure: interpolate(start.pressure, end.pressure, progress),
            glow: interpolate(start.glow, end.glow, progress),
            scale: interpolate(start.scale, end.scale, progress)
        )
    }
}

struct KeyboardStageViewport: Equatable, Sendable {
    var focus: KeyboardStagePoint
    var zoom: Float
    var verticalBias: Float

    static func interpolated(
        from start: KeyboardStageViewport,
        to end: KeyboardStageViewport,
        progress: Float
    ) -> KeyboardStageViewport {
        KeyboardStageViewport(
            focus: .interpolated(from: start.focus, to: end.focus, progress: progress),
            zoom: interpolate(start.zoom, end.zoom, progress),
            verticalBias: interpolate(start.verticalBias, end.verticalBias, progress)
        )
    }
}

struct KeyboardStageScene: Equatable, Sendable {
    var layoutID: String
    var layoutBounds: KeyboardStageRect
    var viewport: KeyboardStageViewport
    var keys: [KeyboardStageKey]
    var decorations: [KeyboardStageDecoration]
    var revealTarget: KeyboardStageRevealTarget
    var displayMode: KeyboardStageDisplayMode
    var transitionDuration: TimeInterval

    func replacingDisplayMode(_ displayMode: KeyboardStageDisplayMode) -> KeyboardStageScene {
        var copy = self
        copy.displayMode = displayMode
        guard displayMode.reduceMotion else { return copy }

        copy.keys = copy.keys.map { key in
            var stationaryKey = key
            stationaryKey.pressure = 0
            stationaryKey.scale = 1
            stationaryKey.translation = .zero
            return stationaryKey
        }
        copy.decorations = copy.decorations.compactMap { decoration in
            switch decoration.kind {
            case .capsEcho, .modifierToken:
                return nil
            case .keyboardDeck,
                 .launcherCandidateMarker,
                 .applicationTarget,
                 .launcherChoiceTarget,
                 .handoffTarget:
                var stationaryDecoration = decoration
                stationaryDecoration.pressure = 0
                stationaryDecoration.scale = 1
                return stationaryDecoration
            }
        }
        return copy
    }

    static func interpolated(
        from start: KeyboardStageScene,
        to end: KeyboardStageScene,
        progress rawProgress: Float
    ) -> KeyboardStageScene {
        let progress = min(1, max(0, rawProgress))
        guard progress > 0 else { return start }
        guard progress < 1 else { return end }
        guard start.layoutID == end.layoutID else {
            return progress < 0.5 ? start : end
        }

        return KeyboardStageScene(
            layoutID: end.layoutID,
            layoutBounds: .interpolated(
                from: start.layoutBounds,
                to: end.layoutBounds,
                progress: progress
            ),
            viewport: .interpolated(from: start.viewport, to: end.viewport, progress: progress),
            keys: interpolateKeys(from: start.keys, to: end.keys, progress: progress),
            decorations: interpolateDecorations(
                from: start.decorations,
                to: end.decorations,
                progress: progress
            ),
            revealTarget: progress < 0.5 ? start.revealTarget : end.revealTarget,
            displayMode: end.displayMode,
            transitionDuration: end.transitionDuration
        )
    }

    private static func interpolateKeys(
        from start: [KeyboardStageKey],
        to end: [KeyboardStageKey],
        progress: Float
    ) -> [KeyboardStageKey] {
        let startByID = Dictionary(uniqueKeysWithValues: start.map { ($0.id, $0) })
        let endIDs = Set(end.map(\.id))
        var result = end.map { key in
            let source = startByID[key.id] ?? key.fadedOut()
            return KeyboardStageKey.interpolated(from: source, to: key, progress: progress)
        }

        result.append(contentsOf: start.compactMap { key in
            guard !endIDs.contains(key.id) else { return nil }
            return KeyboardStageKey.interpolated(
                from: key,
                to: key.fadedOut(),
                progress: progress
            )
        })
        return result
    }

    private static func interpolateDecorations(
        from start: [KeyboardStageDecoration],
        to end: [KeyboardStageDecoration],
        progress: Float
    ) -> [KeyboardStageDecoration] {
        let startByID = Dictionary(uniqueKeysWithValues: start.map { ($0.id, $0) })
        let endIDs = Set(end.map(\.id))
        var result = end.map { decoration in
            let source = startByID[decoration.id] ?? decoration.fadedOut()
            return KeyboardStageDecoration.interpolated(
                from: source,
                to: decoration,
                progress: progress
            )
        }

        result.append(contentsOf: start.compactMap { decoration in
            guard !endIDs.contains(decoration.id) else { return nil }
            return KeyboardStageDecoration.interpolated(
                from: decoration,
                to: decoration.fadedOut(),
                progress: progress
            )
        })
        return result
    }
}

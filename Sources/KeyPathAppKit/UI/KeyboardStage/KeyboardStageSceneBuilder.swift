import Foundation

enum KeyboardStageMoment: Equatable, Sendable {
    case welcome
    case capsMotivation
    case capsApplying
    case capsInstalled
    case hyperMotivation
    case hyperApplying
    case hyperInstalled
    case launcher
    case handoff
}

@MainActor
enum KeyboardStageSceneBuilder {
    struct Application: Equatable, Sendable {
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

        var target: KeyboardStageApplicationTarget {
            KeyboardStageApplicationTarget(
                name: name,
                bundleIdentifier: bundleIdentifier,
                fallbackSystemImage: fallbackSystemImage
            )
        }
    }

    typealias Moment = KeyboardStageMoment

    static func make(
        layout: PhysicalLayout,
        moment: Moment,
        displayMode: KeyboardStageDisplayMode = .standard
    ) -> KeyboardStageScene {
        make(
            layout: layout,
            keymap: .qwertyUS,
            includePunctuation: true,
            moment: moment,
            displayMode: displayMode
        )
    }

    static func make(
        layout: PhysicalLayout,
        keymap: LogicalKeymap,
        includePunctuation: Bool = true,
        moment: Moment,
        displayMode: KeyboardStageDisplayMode = .standard
    ) -> KeyboardStageScene {
        var keys = baseKeys(
            layout: layout,
            keymap: keymap,
            includePunctuation: includePunctuation
        )
        let layoutBounds = bounds(for: keys, fallbackLayout: layout)
        let capsIndex = keys.firstIndex { $0.keyCode == KeyCode.capsLock }
        let capsKeyID = capsIndex.map { keys[$0].id }
        let deck = keyboardDeck(bounds: layoutBounds)
        var stageBounds = deck.frame.insetBy(dx: -0.12, dy: -0.12)
        var decorations: [KeyboardStageDecoration] = [deck]
        var revealTarget = KeyboardStageRevealTarget.none
        var viewport = KeyboardStageViewport(
            focus: layoutBounds.center,
            zoom: 1.08,
            verticalBias: 0.08
        )

        switch moment {
        case .welcome:
            if let capsIndex {
                dim(keys: &keys, except: [keys[capsIndex].id], opacity: 0.86)
                keys[capsIndex].role = .recommended
                keys[capsIndex].glow = 0.28
                keys[capsIndex].legend = KeyboardStageLegend(primary: "caps lock")
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 1)
            }

        case .capsMotivation:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: [capsKeyID], opacity: 0.88)
                keys[capsIndex].role = .recommended
                keys[capsIndex].glow = 0.72
                keys[capsIndex].legend = KeyboardStageLegend(primary: "caps lock")
                keys[capsIndex].accessibilityRole = .capsToEscape
                revealTarget = .capsToEscape(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 1)
            }

        case .capsApplying:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: [capsKeyID], opacity: 0.88)
                keys[capsIndex].role = .escape
                keys[capsIndex].pressure = 0.12
                keys[capsIndex].glow = 0.85
                keys[capsIndex].opacity = 1
                keys[capsIndex].scale = 0.78
                keys[capsIndex].translation = KeyboardStagePoint(x: -0.48, y: -0.52)
                keys[capsIndex].legend = KeyboardStageLegend(
                    primary: "esc",
                    previous: "caps lock",
                    transitionProgress: 1
                )
                keys[capsIndex].accessibilityRole = .capsToEscape
                decorations.append(contentsOf: capsEchoes(frame: keys[capsIndex].frame))
                revealTarget = .capsToEscape(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 1)
            }

        case .capsInstalled:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: [capsKeyID], opacity: 0.88)
                keys[capsIndex].role = .escape
                keys[capsIndex].glow = 0.58
                keys[capsIndex].legend = KeyboardStageLegend(primary: "esc")
                keys[capsIndex].accessibilityRole = .capsToEscape
                revealTarget = .capsToEscape(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 1)
            }

        case .hyperMotivation:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: modifierKeyIDs(in: keys).union([capsKeyID]), opacity: 0.86)
                emphasizeModifiers(in: &keys, glow: 0.56)
                keys[capsIndex].role = .escape
                keys[capsIndex].glow = 0.62
                keys[capsIndex].legend = KeyboardStageLegend(primary: "esc")
                keys[capsIndex].accessibilityRole = .capsToHyper
                decorations.append(contentsOf: modifierTokens(
                    keys: keys,
                    capsFrame: keys[capsIndex].frame,
                    progress: 0,
                    opacity: 0.7
                ))
                revealTarget = .capsToHyper(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 0.98)
            }

        case .hyperApplying:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: modifierKeyIDs(in: keys).union([capsKeyID]), opacity: 0.86)
                emphasizeModifiers(in: &keys, glow: 0)
                keys[capsIndex].role = .hyper
                keys[capsIndex].pressure = 0.68
                keys[capsIndex].glow = 0.93
                keys[capsIndex].scale = 0.96
                keys[capsIndex].legend = KeyboardStageLegend(
                    primary: "Hyper",
                    previous: "esc",
                    secondary: "⌃⌥⇧⌘",
                    transitionProgress: 1
                )
                keys[capsIndex].accessibilityRole = .capsToHyper
                decorations.append(contentsOf: modifierTokens(
                    keys: keys,
                    capsFrame: keys[capsIndex].frame,
                    progress: 1,
                    opacity: 0
                ))
                revealTarget = .capsToHyper(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 0.98)
            }

        case .hyperInstalled:
            if let capsIndex, let capsKeyID {
                dim(keys: &keys, except: [capsKeyID], opacity: 0.88)
                keys[capsIndex].role = .hyper
                keys[capsIndex].glow = 0.72
                keys[capsIndex].legend = KeyboardStageLegend(
                    primary: "Hyper",
                    secondary: "⌃⌥⇧⌘"
                )
                keys[capsIndex].accessibilityRole = .capsToHyper
                revealTarget = .capsToHyper(keyID: capsKeyID)
                viewport = capsViewport(capsFrame: keys[capsIndex].frame, bounds: layoutBounds, zoom: 1)
            }

        case .launcher:
            let candidateKeyCodes = Set(keymap.coreLabels.compactMap { entry -> UInt16? in
                let (keyCode, label) = entry
                guard label.count == 1, label.first?.isLetter == true else { return nil }
                return keyCode
            })
            let candidateIndices = keys.indices.filter { candidateKeyCodes.contains(keys[$0].keyCode) }
            var emphasizedKeyIDs = Set(candidateIndices.map { keys[$0].id })
            if let capsIndex {
                emphasizedKeyIDs.insert(keys[capsIndex].id)
            }
            dim(keys: &keys, except: emphasizedKeyIDs, opacity: 0.80)

            for index in candidateIndices {
                keys[index].role = .launcher
                keys[index].glow = 0.22
                keys[index].opacity = 0.88
            }
            if displayMode.differentiateWithoutColor {
                decorations.append(contentsOf: launcherCandidateMarkers(
                    keys: candidateIndices.map { keys[$0] }
                ))
            }
            if let capsIndex {
                keys[capsIndex].role = .hyper
                keys[capsIndex].pressure = 0.42
                keys[capsIndex].glow = 0.7
                keys[capsIndex].opacity = 1
                keys[capsIndex].legend = KeyboardStageLegend(
                    primary: "Hyper",
                    secondary: "⌃⌥⇧⌘"
                )
                keys[capsIndex].accessibilityRole = .capsToHyper
            }

            let target = journeyTarget(
                kind: .launcherChoiceTarget,
                keys: keys,
                bounds: layoutBounds,
                role: .launcher
            )
            decorations.append(target)
            stageBounds = stageBounds.union(target.frame.insetBy(dx: -0.12, dy: -0.12))

            revealTarget = .launcherChoice
            if let capsIndex {
                viewport = capsViewport(
                    capsFrame: keys[capsIndex].frame,
                    bounds: layoutBounds,
                    zoom: 0.94
                )
            }

        case .handoff:
            for index in keys.indices {
                keys[index].opacity = 0.68
                keys[index].glow = 0
                keys[index].role = .dimmed
            }
            if let capsIndex {
                keys[capsIndex].role = .hyper
                keys[capsIndex].pressure = 0.28
                keys[capsIndex].glow = 0.48
                keys[capsIndex].opacity = 1
                keys[capsIndex].legend = KeyboardStageLegend(
                    primary: "Hyper",
                    secondary: "⌃⌥⇧⌘"
                )
                keys[capsIndex].accessibilityRole = .capsToHyper
            }
            let target = journeyTarget(
                kind: .handoffTarget,
                keys: keys,
                bounds: layoutBounds,
                role: .installed
            )
            decorations.append(target)
            stageBounds = stageBounds.union(target.frame.insetBy(dx: -0.12, dy: -0.12))
            revealTarget = .rules
            if let capsIndex {
                viewport = capsViewport(
                    capsFrame: keys[capsIndex].frame,
                    bounds: layoutBounds,
                    zoom: 1
                )
            }
        }

        return KeyboardStageScene(
            layoutID: layout.id,
            layoutBounds: stageBounds,
            viewport: viewport,
            keys: keys,
            decorations: decorations,
            revealTarget: revealTarget,
            displayMode: displayMode,
            transitionDuration: 0.38
        ).replacingDisplayMode(displayMode)
    }

    // MARK: - Base layout

    private static func baseKeys(
        layout: PhysicalLayout,
        keymap: LogicalKeymap,
        includePunctuation: Bool
    ) -> [KeyboardStageKey] {
        layout.keys.enumerated().compactMap { index, key in
            let legend = displayLegend(
                for: key,
                keymap: keymap,
                includePunctuation: includePunctuation
            )

            guard shouldShowInHero(key: key, label: legend.primary) else { return nil }

            return KeyboardStageKey(
                id: "\(layout.id):\(index):\(key.keyCode)",
                keyCode: key.keyCode,
                frame: KeyboardStageRect(
                    x: Float(key.visualX),
                    y: Float(key.visualY),
                    width: Float(key.width),
                    height: Float(key.height)
                ),
                rotationRadians: Float(key.rotation * .pi / 180),
                legend: legend,
                role: KeyCode.modifiers.contains(key.keyCode) ? .modifier : .standard,
                opacity: key.keyCode == PhysicalKey.unmappedKeyCode ? 0.5 : 0.9,
                pressure: 0,
                glow: 0,
                scale: 1,
                translation: .zero,
                accessibilityRole: nil
            )
        }
    }

    private static func shouldShowInHero(key: PhysicalKey, label: String) -> Bool {
        guard key.keyCode != PhysicalKey.unmappedKeyCode else { return false }

        let uppercaseLabel = label.uppercased()
        if uppercaseLabel == "ESC" || uppercaseLabel == "ESCAPE" {
            return false
        }
        if uppercaseLabel.first == "F", Int(uppercaseLabel.dropFirst()) != nil {
            return false
        }
        return true
    }

    private static func displayLegend(
        for key: PhysicalKey,
        keymap: LogicalKeymap,
        includePunctuation: Bool
    ) -> KeyboardStageLegend {
        switch key.keyCode {
        case KeyCode.capsLock:
            return KeyboardStageLegend(primary: "caps lock")
        case KeyCode.tab:
            return KeyboardStageLegend(primary: "Tab")
        case KeyCode.function:
            return KeyboardStageLegend(primary: "fn")
        case KeyCode.leftControl, KeyCode.rightControl:
            return KeyboardStageLegend(primary: "control")
        case KeyCode.leftOption, KeyCode.rightOption:
            return KeyboardStageLegend(primary: "option")
        case KeyCode.leftShift, KeyCode.rightShift:
            return KeyboardStageLegend(primary: "shift")
        case KeyCode.leftCommand, KeyCode.rightCommand:
            return KeyboardStageLegend(primary: "⌘", secondary: "command")
        default:
            let label = keymap.displayLabel(for: key, includeExtraKeys: includePunctuation)
            return KeyboardStageLegend(
                primary: label.count == 1 ? label.uppercased() : label.capitalized
            )
        }
    }

    private static func bounds(
        for keys: [KeyboardStageKey],
        fallbackLayout: PhysicalLayout
    ) -> KeyboardStageRect {
        guard let first = keys.first else {
            return KeyboardStageRect(
                x: 0,
                y: 0,
                width: Float(max(1, fallbackLayout.totalWidth)),
                height: Float(max(1, fallbackLayout.totalHeight))
            )
        }
        return keys.dropFirst().reduce(first.frame) { partial, key in
            partial.union(key.frame)
        }
    }

    // MARK: - Moment composition

    private static func keyboardDeck(bounds: KeyboardStageRect) -> KeyboardStageDecoration {
        KeyboardStageDecoration(
            id: "keyboard-deck",
            kind: .keyboardDeck,
            frame: KeyboardStageRect(
                x: bounds.minX - 0.22,
                y: bounds.minY - 0.24,
                width: bounds.size.width + 0.44,
                height: bounds.size.height + 0.5
            ),
            rotationRadians: 0,
            role: .deck,
            opacity: 0.98,
            pressure: 0,
            glow: 0.08,
            scale: 1
        )
    }

    private static func dim(
        keys: inout [KeyboardStageKey],
        except keyIDs: Set<String>,
        opacity: Float
    ) {
        for index in keys.indices where !keyIDs.contains(keys[index].id) {
            keys[index].opacity = min(keys[index].opacity, opacity)
            if keys[index].role == .standard {
                keys[index].role = .dimmed
            }
        }
    }

    private static func emphasizeModifiers(in keys: inout [KeyboardStageKey], glow: Float) {
        for index in keys.indices where KeyCode.modifiers.contains(keys[index].keyCode) {
            keys[index].role = .modifier
            keys[index].glow = glow
            keys[index].opacity = max(keys[index].opacity, 0.82)
        }
    }

    private static func modifierKeyIDs(in keys: [KeyboardStageKey]) -> Set<String> {
        Set(keys.lazy.filter { KeyCode.modifiers.contains($0.keyCode) }.map(\.id))
    }

    private static func capsEchoes(frame: KeyboardStageRect) -> [KeyboardStageDecoration] {
        (0 ..< 5).map { index in
            let progress = Float(index) / 5
            return KeyboardStageDecoration(
                id: "caps-role-echo-\(index)",
                kind: .capsEcho(label: index == 0 ? "caps lock" : ""),
                frame: KeyboardStageRect(
                    x: frame.origin.x - 0.48 * progress,
                    y: frame.origin.y - 0.52 * progress,
                    width: frame.size.width,
                    height: frame.size.height
                ),
                rotationRadians: 0,
                role: .recommended,
                opacity: 0.34 - progress * 0.26,
                pressure: 0,
                glow: 0.08,
                scale: 1 - progress * 0.32
            )
        }
    }

    private static func modifierTokens(
        keys: [KeyboardStageKey],
        capsFrame: KeyboardStageRect,
        progress: Float,
        opacity: Float
    ) -> [KeyboardStageDecoration] {
        let descriptors: [(id: String, symbol: String, keyCodes: [UInt16])] = [
            ("control", "⌃", [KeyCode.leftControl, KeyCode.rightControl]),
            ("option", "⌥", [KeyCode.leftOption, KeyCode.rightOption]),
            ("shift", "⇧", [KeyCode.leftShift, KeyCode.rightShift]),
            ("command", "⌘", [KeyCode.leftCommand, KeyCode.rightCommand]),
        ]

        return descriptors.enumerated().compactMap { index, descriptor in
            guard let sourceKey = keys.first(where: { descriptor.keyCodes.contains($0.keyCode) }) else {
                return nil
            }
            // Start as a small badge in the key's upper-left corner so the
            // gathered symbol remains distinct from the native key legend.
            let sourceSize = min(sourceKey.frame.size.width, sourceKey.frame.size.height) * 0.28
            let sourceFrame = KeyboardStageRect(
                x: sourceKey.frame.minX + 0.10,
                y: sourceKey.frame.minY + 0.08,
                width: sourceSize,
                height: sourceSize
            )
            let tokenSize = min(0.46, capsFrame.size.height * 0.44)
            let horizontalInset = min(0.08, capsFrame.size.width * 0.05)
            let availableTravel = max(
                0,
                capsFrame.size.width - tokenSize - horizontalInset * 2
            )
            let destinationStep = availableTravel / Float(max(1, descriptors.count - 1))
            let destinationX = capsFrame.minX + horizontalInset + Float(index) * destinationStep
            let destinationFrame = KeyboardStageRect(
                x: destinationX,
                y: capsFrame.midY - tokenSize / 2,
                width: tokenSize,
                height: tokenSize
            )
            return KeyboardStageDecoration(
                id: "hyper-token-\(descriptor.id)",
                kind: .modifierToken(symbol: descriptor.symbol),
                frame: .interpolated(from: sourceFrame, to: destinationFrame, progress: progress),
                rotationRadians: 0,
                role: .hyper,
                opacity: opacity,
                pressure: 0,
                glow: 0.72,
                scale: 1
            )
        }
    }

    /// Keeps the next real control inside the keyboard's physical world without
    /// covering a useful key legend. Real layouts use a sufficiently wide,
    /// blank spacebar as a restrained target shelf. Compact or incomplete
    /// layouts receive a small shelf just below the deck instead of an overlay.
    private static func journeyTarget(
        kind: KeyboardStageDecoration.Kind,
        keys: [KeyboardStageKey],
        bounds: KeyboardStageRect,
        role: KeyboardStageKeyRole
    ) -> KeyboardStageDecoration {
        let hostKey = keys.first(where: {
            $0.keyCode == KeyCode.space && $0.frame.size.width >= 2.4
        })
            ?? keys
            .filter {
                $0.frame.size.width >= 2.4
                    && $0.legend.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .max(by: { keyArea($0) < keyArea($1) })

        let targetWidth = min(2.75, max(2.2, bounds.size.width * 0.17))
        let targetHeight: Float = 0.66
        let frame: KeyboardStageRect
        if let hostKey {
            let horizontalInset = min(0.16, hostKey.frame.size.width * 0.08)
            let verticalInset = min(0.17, hostKey.frame.size.height * 0.18)
            let availableWidth = max(0.8, hostKey.frame.size.width - horizontalInset * 2)
            let availableHeight = max(0.32, hostKey.frame.size.height - verticalInset * 2)
            let resolvedHeight = min(targetHeight, availableHeight)
            frame = KeyboardStageRect(
                x: hostKey.frame.minX + horizontalInset,
                y: hostKey.frame.midY - resolvedHeight / 2,
                width: min(targetWidth, availableWidth),
                height: resolvedHeight
            )
        } else {
            let capsMaxX = keys.first(where: { $0.keyCode == KeyCode.capsLock })?.frame.maxX
                ?? bounds.minX
            let proposedX = capsMaxX + max(0.55, bounds.size.width * 0.12)
            frame = KeyboardStageRect(
                x: min(bounds.maxX - targetWidth, proposedX),
                y: bounds.maxY + 0.18,
                width: targetWidth,
                height: targetHeight
            )
        }

        return KeyboardStageDecoration(
            id: "keyboard-journey-target",
            kind: kind,
            frame: frame,
            rotationRadians: 0,
            role: role,
            opacity: 0.96,
            pressure: 0.08,
            glow: 0.24,
            scale: 1
        )
    }

    private static func keyArea(_ key: KeyboardStageKey) -> Float {
        key.frame.size.width * key.frame.size.height
    }

    private static func launcherCandidateMarkers(
        keys: [KeyboardStageKey]
    ) -> [KeyboardStageDecoration] {
        keys.map { key in
            let markerSize = min(0.16, key.frame.size.height * 0.16)
            return KeyboardStageDecoration(
                id: "launcher-candidate-marker-\(key.id)",
                kind: .launcherCandidateMarker(keyID: key.id),
                frame: KeyboardStageRect(
                    x: key.frame.maxX - markerSize - 0.10,
                    y: key.frame.minY + 0.09,
                    width: markerSize,
                    height: markerSize
                ),
                rotationRadians: key.rotationRadians,
                role: .deck,
                opacity: 0.94,
                pressure: 0,
                glow: 0,
                scale: 1
            )
        }
    }

    private static func capsViewport(
        capsFrame: KeyboardStageRect,
        bounds: KeyboardStageRect,
        zoom: Float
    ) -> KeyboardStageViewport {
        KeyboardStageViewport(
            focus: KeyboardStagePoint(
                x: min(bounds.maxX, capsFrame.midX + bounds.size.width * 0.17),
                y: min(bounds.maxY, capsFrame.midY + bounds.size.height * 0.04)
            ),
            zoom: zoom,
            verticalBias: 0.08
        )
    }

    private enum KeyCode {
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let leftCommand: UInt16 = 55
        static let leftShift: UInt16 = 56
        static let capsLock: UInt16 = 57
        static let leftOption: UInt16 = 58
        static let leftControl: UInt16 = 59
        static let rightShift: UInt16 = 60
        static let rightOption: UInt16 = 61
        static let rightControl: UInt16 = 62
        static let function: UInt16 = 63
        static let rightCommand: UInt16 = 54

        static let modifiers: Set<UInt16> = [
            leftCommand,
            rightCommand,
            leftShift,
            rightShift,
            leftOption,
            rightOption,
            leftControl,
            rightControl,
        ]
    }
}

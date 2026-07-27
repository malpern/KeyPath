import AppKit
import KeyPathInstallationWizard
import SwiftUI

struct FirstSuccessOnboardingColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(_ red: Int, _ green: Int, _ blue: Int, alpha: Double = 1) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func interpolated(to destination: Self, progress: Float) -> Self {
        let amount = Double(min(1, max(0, progress)))
        guard amount > 0 else { return self }
        guard amount < 1 else { return destination }
        return Self(
            red: red + (destination.red - red) * amount,
            green: green + (destination.green - green) * amount,
            blue: blue + (destination.blue - blue) * amount,
            alpha: alpha + (destination.alpha - alpha) * amount
        )
    }
}

struct FirstSuccessOnboardingPalette: Equatable, Sendable {
    var ambientLight: Float
    var backgroundLeading: FirstSuccessOnboardingColor
    var backgroundTrailing: FirstSuccessOnboardingColor
    var primaryText: FirstSuccessOnboardingColor
    var summaryText: FirstSuccessOnboardingColor
    var detailText: FirstSuccessOnboardingColor
    var mutedText: FirstSuccessOnboardingColor
    var separator: FirstSuccessOnboardingColor
    var inactiveProgress: FirstSuccessOnboardingColor
    var iconSurface: FirstSuccessOnboardingColor
    var accent: FirstSuccessOnboardingColor

    var nativeColorScheme: ColorScheme {
        ambientLight < 0.98 ? .dark : .light
    }

    static let dark = FirstSuccessOnboardingPalette(
        ambientLight: 0,
        backgroundLeading: FirstSuccessOnboardingColor(8, 11, 17),
        backgroundTrailing: FirstSuccessOnboardingColor(15, 19, 28),
        primaryText: FirstSuccessOnboardingColor(239, 243, 250),
        summaryText: FirstSuccessOnboardingColor(187, 196, 210),
        detailText: FirstSuccessOnboardingColor(174, 184, 200),
        mutedText: FirstSuccessOnboardingColor(143, 154, 173),
        separator: FirstSuccessOnboardingColor(43, 51, 66),
        inactiveProgress: FirstSuccessOnboardingColor(62, 71, 88),
        iconSurface: FirstSuccessOnboardingColor(21, 27, 38),
        accent: FirstSuccessOnboardingColor(55, 139, 255)
    )

    static let light = FirstSuccessOnboardingPalette(
        ambientLight: 1,
        backgroundLeading: FirstSuccessOnboardingColor(244, 243, 243),
        backgroundTrailing: FirstSuccessOnboardingColor(247, 246, 246),
        primaryText: FirstSuccessOnboardingColor(43, 42, 42),
        summaryText: FirstSuccessOnboardingColor(102, 101, 101),
        detailText: FirstSuccessOnboardingColor(108, 107, 107),
        mutedText: FirstSuccessOnboardingColor(112, 111, 111),
        separator: FirstSuccessOnboardingColor(216, 215, 215),
        inactiveProgress: FirstSuccessOnboardingColor(205, 205, 205),
        iconSurface: FirstSuccessOnboardingColor(254, 254, 254),
        accent: FirstSuccessOnboardingColor(37, 127, 254)
    )

    static func resolve(ambientLight: Float, increaseContrast: Bool) -> Self {
        let progress = min(1, max(0, ambientLight))
        // Foregrounds do not travel through middle gray alongside the room.
        // They retain their dark-room contrast until the feathered exposure
        // has passed the copy column, then resolve directly to reference-light.
        let foregroundProgress: Float = progress < 0.98 ? 0 : 1
        var palette = Self(
            ambientLight: progress,
            backgroundLeading: dark.backgroundLeading.interpolated(
                to: light.backgroundLeading,
                progress: progress
            ),
            backgroundTrailing: dark.backgroundTrailing.interpolated(
                to: light.backgroundTrailing,
                progress: progress
            ),
            primaryText: dark.primaryText.interpolated(
                to: light.primaryText,
                progress: foregroundProgress
            ),
            summaryText: dark.summaryText.interpolated(
                to: light.summaryText,
                progress: foregroundProgress
            ),
            detailText: dark.detailText.interpolated(
                to: light.detailText,
                progress: foregroundProgress
            ),
            mutedText: dark.mutedText.interpolated(
                to: light.mutedText,
                progress: foregroundProgress
            ),
            separator: dark.separator.interpolated(to: light.separator, progress: progress),
            inactiveProgress: dark.inactiveProgress.interpolated(
                to: light.inactiveProgress,
                progress: progress
            ),
            iconSurface: dark.iconSurface.interpolated(to: light.iconSurface, progress: progress),
            accent: dark.accent.interpolated(to: light.accent, progress: progress)
        )

        if increaseContrast {
            let darkHighContrast = FirstSuccessOnboardingColor(255, 255, 255)
            let lightHighContrast = FirstSuccessOnboardingColor(0, 0, 0)
            let lightSecondaryHighContrast = FirstSuccessOnboardingColor(58, 57, 57)
            palette.primaryText = darkHighContrast.interpolated(
                to: lightHighContrast,
                progress: foregroundProgress
            )
            palette.summaryText = darkHighContrast.interpolated(
                to: lightSecondaryHighContrast,
                progress: foregroundProgress
            )
            palette.detailText = darkHighContrast.interpolated(
                to: lightSecondaryHighContrast,
                progress: foregroundProgress
            )
            palette.mutedText = darkHighContrast.interpolated(
                to: lightSecondaryHighContrast,
                progress: foregroundProgress
            )
        }
        return palette
    }
}

enum FirstSuccessOnboardingStyle {
    static let initialBackgroundNSColor = FirstSuccessOnboardingPalette.dark.backgroundLeading.nsColor
}

private struct FirstSuccessOnboardingPaletteKey: EnvironmentKey {
    static let defaultValue = FirstSuccessOnboardingPalette.light
}

private extension EnvironmentValues {
    var firstSuccessOnboardingPalette: FirstSuccessOnboardingPalette {
        get { self[FirstSuccessOnboardingPaletteKey.self] }
        set { self[FirstSuccessOnboardingPaletteKey.self] = newValue }
    }
}

private struct FirstSuccessWindowBackgroundBridge: NSViewRepresentable {
    let backgroundColor: NSColor

    func makeNSView(context _: Context) -> FirstSuccessWindowBackgroundView {
        FirstSuccessWindowBackgroundView(backgroundColor: backgroundColor)
    }

    func updateNSView(_ view: FirstSuccessWindowBackgroundView, context _: Context) {
        view.backgroundColor = backgroundColor
    }
}

private struct FirstSuccessCinematicLightWash: View {
    let progress: Float

    var body: some View {
        let amount = Double(min(1, max(0, progress)))
        let front = 1.36 - amount * 1.72

        LinearGradient(
            colors: [
                FirstSuccessOnboardingPalette.light.backgroundLeading.color,
                FirstSuccessOnboardingPalette.light.backgroundTrailing.color,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: UnitPoint(x: front - 0.28, y: 0.5),
                endPoint: UnitPoint(x: front + 0.28, y: 0.5)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class FirstSuccessWindowBackgroundView: NSView {
    var backgroundColor: NSColor {
        didSet { applyWindowBackground() }
    }

    init(backgroundColor: NSColor) {
        self.backgroundColor = backgroundColor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowBackground()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func applyWindowBackground() {
        window?.backgroundColor = backgroundColor
    }
}

/// The optional first-success journey shown after KeyPath's first healthy setup.
/// Native SwiftUI owns copy, controls, focus, and accessibility. The persistent
/// keyboard hero is fed by the same scene model in both SwiftUI and Metal.
@MainActor
struct FirstSuccessOnboardingDialog: View {
    let actionCoordinator: FirstSuccessOnboardingActionCoordinator
    let makeCapsLockEscape: @MainActor @Sendable () async -> FirstSuccessOnboardingSession.ActionResult
    let addHyperHold: @MainActor @Sendable () async -> FirstSuccessOnboardingSession.ActionResult
    let openCapsLockControls: () -> Void
    let finishInRules: () -> Void
    let dismiss: () -> Void

    @State private var keyboardInput = FirstSuccessKeyboardInputCoordinator()
    @State private var keyboardEntrance = KeyboardStageEntranceController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var session: FirstSuccessOnboardingSession {
        actionCoordinator.session
    }

    var body: some View {
        TimelineView(.animation(paused: !keyboardEntrance.presentation.isAnimating)) { _ in
            let entranceFrame = keyboardEntrance.presentation.frame(
                at: ProcessInfo.processInfo.systemUptime,
                pendingReduceMotion: reduceMotion
            )
            let ambientLight = KeyboardStageCinematicLighting.exposure(
                for: entranceFrame,
                normalizedX: 0.18
            )
            let palette = FirstSuccessOnboardingPalette.resolve(
                ambientLight: ambientLight,
                increaseContrast: colorSchemeContrast == .increased
            )
            let basePalette = entranceFrame.reduceMotion
                ? palette
                : entranceFrame.progress >= 1
                ? FirstSuccessOnboardingPalette.light
                : FirstSuccessOnboardingPalette.dark

            dialogContent
                .foregroundStyle(palette.primaryText.color)
                .tint(palette.accent.color)
                .background {
                    ZStack {
                        LinearGradient(
                            colors: [
                                basePalette.backgroundLeading.color,
                                basePalette.backgroundTrailing.color,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        if !entranceFrame.reduceMotion {
                            FirstSuccessCinematicLightWash(
                                progress: entranceFrame.progress
                            )
                        }
                    }
                    .ignoresSafeArea()
                    .background {
                        FirstSuccessWindowBackgroundBridge(
                            backgroundColor: basePalette.backgroundLeading.nsColor
                        )
                    }
                }
                .environment(\.firstSuccessOnboardingPalette, palette)
                // Native controls begin in their dark treatment, then switch
                // late in the ambient-light rise. Explicit palette colors carry
                // the continuous transition and preserve the exact light endpoint.
                .environment(\.colorScheme, palette.nativeColorScheme)
        }
        .accessibilityIdentifier("first-success-onboarding-dialog")
        .onAppear {
            keyboardInput.start()
        }
        .onDisappear {
            keyboardInput.stop()
            keyboardEntrance.settle()
        }
    }

    private var dialogContent: some View {
        VStack(spacing: 0) {
            FirstSuccessProgressHeader(step: session.step)
            FirstSuccessSeparator(horizontalInset: 36)

            FirstSuccessJourneyContent(
                session: session,
                keyboardInput: keyboardInput,
                keyboardEntrance: keyboardEntrance,
                displayMode: displayMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FirstSuccessStatusRegion(
                session: session,
                openCapsLockControls: openCapsLockControls,
                openLauncherControls: finishInRules
            )

            FirstSuccessSeparator(horizontalInset: 14)
            WizardButtonBar(
                cancel: .init(
                    title: String(
                        localized: "Skip tour",
                        bundle: #bundle,
                        comment: "Button that dismisses the optional first-success tour."
                    ),
                    action: skipTour,
                    isEnabled: actionCoordinator.buttonState.skipTourEnabled,
                    usesCancelShortcut: false
                ),
                secondary: .init(
                    title: String(
                        localized: "Back",
                        bundle: #bundle,
                        comment: "Button that returns to the previous first-success lesson."
                    ),
                    action: goBack,
                    isEnabled: actionCoordinator.buttonState.backEnabled
                ),
                primary: .init(
                    title: String(localized: primaryTitle),
                    action: performPrimaryAction,
                    isEnabled: actionCoordinator.buttonState.primaryEnabled,
                    isLoading: actionCoordinator.isActionInFlight
                ),
                secondaryPlacement: .trailing
            )
            .accessibilityIdentifier("first-success-onboarding-button-bar")
        }
        .frame(minWidth: 960, idealWidth: 1120, minHeight: 650, idealHeight: 720)
    }

    private var displayMode: KeyboardStageDisplayMode {
        KeyboardStageDisplayMode(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private var primaryTitle: LocalizedStringResource {
        switch session.step {
        case .capsLock:
            switch session.capsLockPhase {
            case .installed, .practiced:
                LocalizedStringResource("Continue", bundle: #bundle)
            case .blocked:
                LocalizedStringResource("Open Caps Lock controls", bundle: #bundle)
            case .explaining where session.failure == .capsLockEscape:
                LocalizedStringResource("Try again", bundle: #bundle)
            case .explaining, .applying:
                LocalizedStringResource("Use Caps Lock for Escape", bundle: #bundle)
            }
        case .hyper:
            switch session.hyperPhase {
            case .installed, .practiced:
                LocalizedStringResource("Continue", bundle: #bundle)
            case .blocked:
                LocalizedStringResource("Open Quick Launcher controls", bundle: #bundle)
            case .explaining where session.failure == .hyper:
                LocalizedStringResource("Try again", bundle: #bundle)
            case .explaining, .applying:
                LocalizedStringResource("Add Hyper on hold", bundle: #bundle)
            }
        case .launcher:
            LocalizedStringResource("Continue", bundle: #bundle)
        case .rules:
            LocalizedStringResource("Choose an app and key", bundle: #bundle)
        }
    }

    private func performPrimaryAction() {
        guard actionCoordinator.buttonState.primaryEnabled else { return }
        switch session.step {
        case .capsLock:
            switch session.capsLockPhase {
            case .installed, .practiced:
                moveForward()
            case .blocked:
                openCapsLockControls()
            case .explaining:
                run(.capsLockEscape, action: makeCapsLockEscape)
            case .applying:
                break
            }
        case .hyper:
            switch session.hyperPhase {
            case .installed, .practiced:
                moveForward()
            case .blocked:
                finishInRules()
            case .explaining:
                run(.hyper, action: addHyperHold)
            case .applying:
                break
            }
        case .launcher:
            moveForward()
        case .rules:
            finishInRules()
        }
    }

    private func run(
        _ kind: FirstSuccessOnboardingSession.ActionKind,
        action: @escaping @MainActor @Sendable () async -> FirstSuccessOnboardingSession.ActionResult
    ) {
        actionCoordinator.start(kind, action: action)
    }

    private func moveForward() {
        // The keyboard hero owns its critically damped transition. Applying a
        // broad SwiftUI animation here also cross-fades stable labels and action
        // bar controls, which can leave them briefly blank during page changes.
        actionCoordinator.moveForward()
    }

    private func goBack() {
        actionCoordinator.moveBack()
    }

    private func skipTour() {
        actionCoordinator.requestDismiss(perform: dismiss)
    }
}

private struct FirstSuccessSeparator: View {
    let horizontalInset: CGFloat
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.separator.color)
            .frame(height: 1)
            .padding(.horizontal, horizontalInset)
            .accessibilityHidden(true)
    }
}

private struct FirstSuccessProgressHeader: View {
    let step: FirstSuccessOnboardingSession.Step
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(FirstSuccessOnboardingSession.Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(
                            item.rawValue <= step.rawValue
                                ? palette.accent.color
                                : palette.inactiveProgress.color
                        )
                        .frame(width: 9, height: 9)
                        .scaleEffect(item == step ? 1 : 0.88)
                }
            }
            .accessibilityHidden(true)

            Text("\(step.ordinal) of \(FirstSuccessOnboardingSession.Step.allCases.count)", bundle: #bundle)
                .font(.caption)
                .foregroundStyle(palette.mutedText.color)
                .padding(.leading, 28)

            Spacer()
        }
        .padding(.horizontal, 42)
        .frame(minHeight: 68)
        .offset(y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "Onboarding step \(step.ordinal) of \(FirstSuccessOnboardingSession.Step.allCases.count)",
                bundle: #bundle
            )
        )
        .accessibilityIdentifier("first-success-onboarding-progress")
    }
}

private struct FirstSuccessJourneyContent: View {
    let session: FirstSuccessOnboardingSession
    let keyboardInput: FirstSuccessKeyboardInputCoordinator
    let keyboardEntrance: KeyboardStageEntranceController
    let displayMode: KeyboardStageDisplayMode

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedContent
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 26) {
                            FirstSuccessLessonCopy(
                                session: session,
                                capsTapRevision: keyboardInput.capsTapRevision
                            )
                            .frame(
                                width: min(370, geometry.size.width * 0.34),
                                alignment: .leading
                            )

                            FirstSuccessKeyboardHero(
                                session: session,
                                interaction: keyboardInput.interaction,
                                entrance: keyboardEntrance,
                                displayMode: displayMode
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, -16)
                            .offset(y: 8)
                        }

                        stackedContent
                    }
                }
            }
            .padding(.leading, 42)
            .padding(.trailing, 0)
            .padding(.vertical, 40)
        }
    }

    private var stackedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                FirstSuccessLessonCopy(
                    session: session,
                    capsTapRevision: keyboardInput.capsTapRevision
                )
                FirstSuccessKeyboardHero(
                    session: session,
                    interaction: keyboardInput.interaction,
                    entrance: keyboardEntrance,
                    displayMode: displayMode
                )
                .frame(minHeight: 330)
            }
            .padding(.trailing, 42)
        }
    }
}

private struct FirstSuccessLessonCopy: View {
    let session: FirstSuccessOnboardingSession
    let capsTapRevision: UInt64
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.step.eyebrow)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.accent.color)
                    .tracking(0.6)

                Text(session.step.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(palette.primaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)

                Text(session.step.summary)
                    .font(.body)
                    .foregroundStyle(palette.summaryText.color)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                FirstSuccessBenefits(
                    session: session,
                    capsTapRevision: capsTapRevision
                )
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-success-onboarding-copy")
    }
}

private struct FirstSuccessBenefits: View {
    let session: FirstSuccessOnboardingSession
    let capsTapRevision: UInt64
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch session.step {
            case .capsLock:
                FirstSuccessBenefitRow(
                    icon: "keypath.esc",
                    title: "Escape at your fingertips",
                    detail: "Close menus, dismiss search, and cancel cleanly without reaching across the keyboard.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "shield",
                    title: session.hyperPhase.isInstalled
                        ? "Your hold shortcut stays Hyper"
                        : "Keep what you need",
                    detail: session.hyperPhase.isInstalled
                        ? "Holding Caps Lock still prepares Hyper. You can change or turn off either action in Rules at any time."
                        : "Hold Caps Lock when you want its original action. You can change or turn this off in Rules at any time.",
                    tone: palette.accent.color
                )
                CapsLockPracticeControl(
                    session: session,
                    capsTapRevision: capsTapRevision
                )

            case .hyper:
                FirstSuccessBenefitRow(
                    icon: "command",
                    title: "That prefix is Hyper",
                    detail: "Hyper means Control + Option + Shift + Command together.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "sparkles",
                    title: "Shortcuts without collisions",
                    detail: "Apps rarely reserve the full combination, so it is a clean prefix for shortcuts you choose.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "hand.tap",
                    title: session.hyperPhase.isInstalled ? "Ready to use" : "Tap stays Escape",
                    detail: session.hyperPhase.isInstalled
                        ? "Tap Caps Lock for Escape. Hold it when you want a KeyPath shortcut."
                        : "The first win stays in place. Holding the same key adds a second job.",
                    tone: session.hyperPhase.isInstalled
                        ? palette.accent.color
                        : palette.mutedText.color
                )

            case .launcher:
                FirstSuccessBenefitRow(
                    icon: "arrow.up.forward.app",
                    title: "Your app, your key",
                    detail: "Choose a letter you will remember and assign the app or website you actually use.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "keyboard",
                    title: "One simple gesture",
                    detail: "Hold Caps Lock, press your chosen letter, then release. No Dock or mouse needed.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "slider.horizontal.3",
                    title: "Nothing is locked in",
                    detail: "Quick Launcher keeps every assignment visible and editable in Rules.",
                    tone: palette.mutedText.color
                )

            case .rules:
                FirstSuccessBenefitRow(
                    icon: "cursorarrow.click.2",
                    title: "Choose in the real controls",
                    detail: "KeyPath will open Quick Launcher, where you select a key and the app or website it should open.",
                    tone: palette.accent.color
                )
                FirstSuccessBenefitRow(
                    icon: "square.grid.2x2",
                    title: "Keep exploring from there",
                    detail: "The Rules sidebar is also where you can discover, change, or disable every remap.",
                    tone: palette.mutedText.color
                )
            }
        }
    }
}

private struct FirstSuccessBenefitRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let tone: Color
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            iconContent
                .foregroundStyle(tone)
                .frame(width: 44, height: 44)
                .background(
                    palette.iconSurface.color.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tone.opacity(0.72), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title, bundle: #bundle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                Text(detail, bundle: #bundle)
                    .font(.callout)
                    .foregroundStyle(palette.detailText.color)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var iconContent: some View {
        if icon == "keypath.esc" {
            Text("esc", bundle: #bundle)
                .font(.system(size: 16, weight: .semibold))
        } else {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
        }
    }
}

private struct CapsLockPracticeControl: View {
    @Bindable var session: FirstSuccessOnboardingSession
    let capsTapRevision: UInt64

    @State private var armedTapRevision: UInt64?
    @State private var disarmTask: Task<Void, Never>?
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        if session.capsLockPhase.isInstalled {
            Button {
                disarmTask?.cancel()
                armedTapRevision = capsTapRevision
                session.isCapsPracticeMenuPresented = true
            } label: {
                FirstSuccessBenefitRow(
                    icon: session.capsLockPhase == .practiced ? "arrow.counterclockwise" : "menucard",
                    title: session.capsLockPhase == .practiced ? "Try it again" : "Try it now",
                    detail: session.capsLockPhase == .practiced
                        ? "If Caps Lock closed the menu, its new Escape action worked. Open it again whenever you want."
                        : "Open the practice menu, then tap your physical Caps Lock key to dismiss it.",
                    tone: palette.accent.color
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $session.isCapsPracticeMenuPresented, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A tiny practice menu", bundle: #bundle)
                        .font(.headline)
                    Text("Tap Caps Lock. It should dismiss this menu just like Escape.", bundle: #bundle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(width: 260, alignment: .leading)
                .accessibilityIdentifier("first-success-caps-practice-menu")
            }
            .onChange(of: session.isCapsPracticeMenuPresented) { wasPresented, isPresented in
                if wasPresented, !isPresented {
                    scheduleDisarm()
                }
            }
            .onChange(of: capsTapRevision) { _, revision in
                guard let armedTapRevision, revision > armedTapRevision else { return }
                disarmTask?.cancel()
                disarmTask = nil
                self.armedTapRevision = nil
                session.markCapsLockPracticed()
                session.isCapsPracticeMenuPresented = false
            }
            .onDisappear {
                disarmTask?.cancel()
                disarmTask = nil
                armedTapRevision = nil
            }
            .accessibilityIdentifier("first-success-caps-practice-button")
        } else {
            FirstSuccessBenefitRow(
                icon: "keyboard",
                title: "Try the real key",
                detail: "After KeyPath saves the change, you can test Caps Lock against a practice menu here.",
                tone: palette.mutedText.color
            )
        }
    }

    private func scheduleDisarm() {
        guard armedTapRevision != nil else { return }
        disarmTask?.cancel()
        disarmTask = Task { @MainActor in
            try? await Task<Never, Never>.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            armedTapRevision = nil
            disarmTask = nil
        }
    }
}

private struct FirstSuccessStatusRegion: View {
    let session: FirstSuccessOnboardingSession
    let openCapsLockControls: () -> Void
    let openLauncherControls: () -> Void
    @Environment(\.firstSuccessOnboardingPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            if session.isApplying {
                ProgressView()
                    .controlSize(.small)
                Text("Saving and reloading your keyboard…", bundle: #bundle)
                    .font(.callout)
                    .foregroundStyle(palette.detailText.color)
            } else if let failure = session.failure {
                Image(systemName: session.currentPhase == .blocked ? "shield.lefthalf.filled" : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        session.currentPhase == .blocked
                            ? palette.accent.color
                            : WizardDesign.Colors.warning
                    )
                    .accessibilityHidden(true)

                Text(failureMessage(for: failure))
                    .font(.subheadline)
                    .foregroundStyle(palette.detailText.color)

                if session.currentPhase == .blocked {
                    Button {
                        switch failure {
                        case .capsLockEscape: openCapsLockControls()
                        case .hyper: openLauncherControls()
                        }
                    } label: {
                        Text("Open Rules", bundle: #bundle)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("first-success-open-rules-after-conflict")
                }
            }

            Spacer()
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 42)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-success-onboarding-status")
    }

    private func failureMessage(
        for failure: FirstSuccessOnboardingSession.ActionKind
    ) -> LocalizedStringResource {
        if session.currentPhase == .blocked {
            return switch failure {
            case .capsLockEscape:
                LocalizedStringResource(
                    "Caps Lock already has a custom job, so KeyPath left it untouched.",
                    bundle: #bundle,
                    comment: "Safe conflict message when onboarding will not overwrite Caps Lock."
                )
            case .hyper:
                LocalizedStringResource(
                    "Quick Launcher already has custom settings, so KeyPath left them untouched.",
                    bundle: #bundle,
                    comment: "Safe conflict message when onboarding will not overwrite Quick Launcher."
                )
            }
        }

        if session.savedButNotActive == failure {
            return LocalizedStringResource(
                "Your choice was saved, but KeyPath could not make it active yet. Try again or continue in Rules.",
                bundle: #bundle,
                comment: "Recoverable error shown when an onboarding choice is durable but its live reload is not active."
            )
        }

        return LocalizedStringResource(
            "KeyPath could not save that change. Nothing new was applied; try again or continue in Rules.",
            bundle: #bundle,
            comment: "Recoverable error shown when an onboarding catalog install fails."
        )
    }
}

private struct FirstSuccessKeyboardHero: View {
    let session: FirstSuccessOnboardingSession
    let interaction: KeyboardStageInteractionState
    let entrance: KeyboardStageEntranceController
    let displayMode: KeyboardStageDisplayMode

    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutID = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapID = LogicalKeymap.defaultId

    var body: some View {
        let layout = PhysicalLayout.find(id: selectedLayoutID) ?? .macBookUS
        let keymap = LogicalKeymap.resolve(id: selectedKeymapID)
        let scene = KeyboardStageSceneBuilder.make(
            layout: layout,
            keymap: keymap,
            moment: moment,
            displayMode: displayMode
        )

        KeyboardStageHost(
            scene: scene,
            interaction: interaction,
            renderer: .automatic,
            entrance: entrance
        )
        .environment(\.firstSuccessOnboardingPalette, .light)
        .environment(\.colorScheme, .light)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("first-success-keyboard-hero")
    }

    private var moment: KeyboardStageMoment {
        switch session.step {
        case .capsLock:
            switch session.capsLockPhase {
            case .explaining, .blocked: .capsMotivation
            case .applying: .capsApplying
            case .installed, .practiced: .capsInstalled
            }
        case .hyper:
            switch session.hyperPhase {
            case .explaining, .blocked: .hyperMotivation
            case .applying: .hyperApplying
            case .installed, .practiced: .hyperInstalled
            }
        case .launcher:
            .launcher
        case .rules:
            .handoff
        }
    }

    private var accessibilityLabel: Text {
        switch moment {
        case .welcome:
            Text("A keyboard ready for three guided changes.", bundle: #bundle)
        case .capsMotivation:
            Text("Caps Lock is highlighted. It still types Caps Lock; the proposed tap action is Escape.", bundle: #bundle)
        case .capsApplying:
            Text("Caps Lock is being changed to type Escape when tapped.", bundle: #bundle)
        case .capsInstalled:
            if session.hyperPhase.isInstalled {
                Text("Caps Lock types Escape when tapped and prepares Hyper when held.", bundle: #bundle)
            } else {
                Text("Caps Lock now types Escape when tapped. Its hold action remains available and unchanged.", bundle: #bundle)
            }
        case .hyperMotivation:
            Text("Caps Lock types Escape when tapped. The proposed hold action is Hyper.", bundle: #bundle)
        case .hyperApplying:
            Text("Held Caps Lock is being changed to Hyper: Control, Option, Shift, and Command.", bundle: #bundle)
        case .hyperInstalled:
            Text("Caps Lock now types Escape when tapped and Hyper when held.", bundle: #bundle)
        case .launcher:
            Text("Held Caps Lock prepares Hyper, and the highlighted letters are available shortcut keys you can choose.", bundle: #bundle)
        case .handoff:
            Text("The keyboard is ready. The next action opens Quick Launcher, where you will choose an app and key.", bundle: #bundle)
        }
    }
}

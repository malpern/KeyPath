import AppKit
import Observation
import SwiftUI

/// Presentation-only fixtures: deliberately has no rules manager, installer,
/// onboarding gate, or durable preference dependency.
@MainActor
@Observable
final class FirstSuccessTourPreviewModel {
    enum Scenario: String, CaseIterable, Identifiable {
        case fresh = "Fresh"
        case installed = "Installed"
        case selected = "App selected"
        case failed = "Save failed"
        case blocked = "Existing setup"
        case inactive = "Saved, inactive"
        var id: String {
            rawValue
        }
    }

    var coordinator = FirstSuccessOnboardingActionCoordinator()
    var choice = FirstSuccessLauncherChoiceModel()
    private(set) var scenario: Scenario = .fresh
    private(set) var revision = 0

    func select(page: FirstSuccessOnboardingSession.Step, scenario: Scenario) {
        guard coordinator.canDismiss else { return }
        self.scenario = scenario
        let session = FirstSuccessOnboardingSession()
        session.step = page
        if page.rawValue > 0 { session.finish(.capsLockEscape, result: .applied) }
        if page.rawValue > 1 { session.finish(.hyper, result: .applied) }
        choice = FirstSuccessLauncherChoiceModel()
        if scenario != .fresh, scenario != .blocked {
            choice.selectedApp = AppLaunchInfo(
                name: "Safari", bundleIdentifier: "com.apple.Safari",
                icon: NSImage(systemSymbolName: "safari", accessibilityDescription: "Safari") ?? NSImage()
            )
            choice.setCanonicalKey("s")
        }
        let action: FirstSuccessOnboardingSession.ActionKind = switch page {
        case .capsLock: .capsLockEscape
        case .hyper: .hyper
        case .launcher, .rules: .launcherShortcut
        }
        switch scenario {
        case .fresh, .selected: break
        case .installed: session.finish(action, result: .applied)
        case .failed: session.finish(action, result: .failed)
        case .blocked: session.finish(action, result: .needsRules)
        case .inactive: session.finish(action, result: .savedButNotActive)
        }
        coordinator = FirstSuccessOnboardingActionCoordinator(session: session)
        revision += 1
    }

    /// All action buttons exercise the normal presentation flow, never disk.
    func simulateSave() -> FirstSuccessOnboardingSession.ActionResult {
        .applied
    }

    func dialog(close: @escaping () -> Void = {}) -> FirstSuccessOnboardingDialog {
        FirstSuccessOnboardingDialog(
            actionCoordinator: coordinator,
            makeCapsLockEscape: { self.simulateSave() },
            addHyperHold: { self.simulateSave() },
            saveLauncherShortcut: { _ in self.simulateSave() },
            finishInKeyboard: close, dismiss: close, launcherChoice: choice, settledPreview: true
        )
    }
}

struct FirstSuccessTourPreviewView: View {
    @State private var model = FirstSuccessTourPreviewModel()
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Preview · Changes aren’t saved")
                    .font(.caption)
                Picker("Page", selection: Binding(
                    get: { model.coordinator.session.step },
                    set: { model.select(page: $0, scenario: model.scenario) }
                )) {
                    ForEach(FirstSuccessOnboardingSession.Step.allCases, id: \.rawValue) { page in
                        Text("\(page.ordinal)").tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .accessibilityIdentifier("tour-preview-page")
                Picker("State", selection: Binding(
                    get: { model.scenario },
                    set: { model.select(page: model.coordinator.session.step, scenario: $0) }
                )) {
                    ForEach(FirstSuccessTourPreviewModel.Scenario.allCases) { scenario in
                        Text(scenario.rawValue).tag(scenario)
                    }
                }
                .frame(width: 230)
                .accessibilityIdentifier("tour-preview-state")
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .disabled(!model.coordinator.canDismiss)
            Divider()
            model.dialog(close: close)
                .id(model.revision)
        }
        .preferredColorScheme(.light)
    }
}

@MainActor
final class FirstSuccessTourPreviewWindowController: NSWindowController, NSWindowDelegate {
    private static var current: FirstSuccessTourPreviewWindowController?

    static func show() {
        if let current {
            current.showWindow(nil)
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = FirstSuccessTourPreviewWindowController()
        current = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 765),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "KeyPath Tour Preview"
        window.contentMinSize = NSSize(width: 960, height: 695)
        window.center()
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: FirstSuccessTourPreviewView { [weak self] in
            self?.close()
        })
        window.delegate = self
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func windowWillClose(_: Notification) {
        Self.current = nil
    }
}

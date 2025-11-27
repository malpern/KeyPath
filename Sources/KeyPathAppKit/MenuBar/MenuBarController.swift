import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    typealias Handler = () -> Void

    private let statusItem: NSStatusItem
    private let bringToFrontHandler: Handler
    private let showWizardHandler: Handler
    private let uninstallHandler: Handler
    private let quitHandler: Handler
    private let menu: NSMenu
    private var keymapMenuItem: NSMenuItem?
    private var stateController: MainAppStateController?
    private var cancellables = Set<AnyCancellable>()

    init(
        bringToFrontHandler: @escaping Handler,
        showWizardHandler: @escaping Handler,
        uninstallHandler: @escaping Handler,
        quitHandler: @escaping Handler,
        stateController: MainAppStateController? = nil
    ) {
        self.bringToFrontHandler = bringToFrontHandler
        self.showWizardHandler = showWizardHandler
        self.uninstallHandler = uninstallHandler
        self.quitHandler = quitHandler
        self.stateController = stateController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

        configureButton()
        configureMenu()
        observeSystemState()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "KeyPath"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "⌨︎"
        }

        button.imagePosition = .imageOnly
        button.toolTip = "KeyPath"
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.removeAllItems()

        let showItem = NSMenuItem(
            title: "Show KeyPath",
            action: #selector(handleShowKeyPath),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let keymapItem = NSMenuItem(
            title: "See Keymap…",
            action: #selector(handleShowKeymap),
            keyEquivalent: "k"
        )
        keymapItem.keyEquivalentModifierMask = .command
        keymapItem.target = self
        keymapItem.isEnabled = false // Disabled by default until system is green
        if let mapImage = NSImage(systemSymbolName: "map", accessibilityDescription: "Keymap") {
            mapImage.isTemplate = true
            keymapItem.image = mapImage
        }
        keymapMenuItem = keymapItem
        menu.addItem(keymapItem)

        let wizardItem = NSMenuItem(
            title: "Open Install Wizard…",
            action: #selector(handleShowWizard),
            keyEquivalent: ""
        )
        wizardItem.target = self
        menu.addItem(wizardItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: "Uninstall KeyPath…",
            action: #selector(handleUninstall),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(
            title: "Quit KeyPath",
            action: #selector(handleQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func handleShowKeyPath() {
        bringToFrontHandler()
    }

    @objc
    private func handleShowKeymap() {
        KeyboardVisualizationManager.shared.toggle()
    }

    @objc
    private func handleShowWizard() {
        showWizardHandler()
    }

    @objc
    private func handleUninstall() {
        uninstallHandler()
    }

    @objc
    private func handleQuit() {
        quitHandler()
    }

    // MARK: - System State Observation

    private func observeSystemState() {
        guard let stateController else {
            // If no state controller provided, keep menu item disabled
            keymapMenuItem?.isEnabled = false
            return
        }

        // Observe validation state changes
        stateController.$validationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] validationState in
                self?.updateKeymapMenuItemState(validationState: validationState)
            }
            .store(in: &cancellables)

        // Initial state update
        updateKeymapMenuItemState(validationState: stateController.validationState)
    }

    private func updateKeymapMenuItemState(validationState: MainAppStateController.ValidationState?) {
        let isEnabled: Bool = if let state = validationState {
            state.isSuccess
        } else {
            // Not yet validated - keep disabled
            false
        }

        keymapMenuItem?.isEnabled = isEnabled

        if !isEnabled {
            // If disabled and user tries to show visualization, close any open windows
            KeyboardVisualizationManager.shared.hide()
        }
    }

    /// Update the state controller reference (called when MainAppStateController is available)
    func setStateController(_ stateController: MainAppStateController) {
        self.stateController = stateController
        observeSystemState()
    }
}

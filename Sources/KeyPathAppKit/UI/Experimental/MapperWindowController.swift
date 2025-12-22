import AppKit
import SwiftUI

// MARK: - Window Controller

@MainActor
class MapperWindowController {
    private var window: NSWindow?
    private weak var viewModel: KanataViewModel?
    /// Pending preset values to apply when view appears
    private var pendingPresetInput: String?
    private var pendingPresetOutput: String?
    private var pendingLayer: String?
    private var pendingPresetAppIdentifier: String?
    private var pendingPresetSystemActionIdentifier: String?
    private var pendingPresetURLIdentifier: String?

    static let shared = MapperWindowController()

    /// Show the Mapper window, optionally with preset input/output values, layer, and input keyCode from overlay click
    func showWindow(
        viewModel: KanataViewModel,
        presetInput: String? = nil,
        presetOutput: String? = nil,
        layer: String? = nil,
        inputKeyCode: UInt16? = nil,
        appIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil
    ) {
        self.viewModel = viewModel
        pendingPresetInput = presetInput
        pendingPresetOutput = presetOutput
        pendingLayer = layer
        pendingPresetAppIdentifier = appIdentifier
        pendingPresetSystemActionIdentifier = systemActionIdentifier
        pendingPresetURLIdentifier = urlIdentifier

        if let existingWindow = window, existingWindow.isVisible {
            // Window already visible - apply presets to existing view
            if let presetInput, let presetOutput {
                var userInfo: [String: Any] = ["input": presetInput, "output": presetOutput]
                if let layer {
                    userInfo["layer"] = layer
                }
                if let inputKeyCode {
                    userInfo["inputKeyCode"] = inputKeyCode
                }
                if let appIdentifier {
                    userInfo["appIdentifier"] = appIdentifier
                }
                if let systemActionIdentifier {
                    userInfo["systemActionIdentifier"] = systemActionIdentifier
                }
                if let urlIdentifier {
                    userInfo["urlIdentifier"] = urlIdentifier
                }
                NotificationCenter.default.post(
                    name: .mapperPresetValues,
                    object: nil,
                    userInfo: userInfo
                )
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MapperView(
            presetInput: presetInput,
            presetOutput: presetOutput,
            presetLayer: layer,
            presetInputKeyCode: inputKeyCode,
            presetAppIdentifier: appIdentifier,
            presetSystemActionIdentifier: systemActionIdentifier,
            presetURLIdentifier: urlIdentifier
        )
        .environmentObject(viewModel)

        // Window height calculation:
        // - Header: ~30pt
        // - Input keycap (max): 150pt + label 20pt = 170pt
        // - Arrow: ~25pt
        // - Output keycap (max): 150pt + label 20pt = 170pt
        // - Bottom bar: ~35pt
        // - Padding: ~30pt
        // Total: ~460pt for vertical layout with max-height keycaps
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mapper"
        window.minSize = NSSize(width: 340, height: 300)
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        // Persistent window position
        window.setFrameAutosaveName("MapperWindow")
        if !window.setFrameUsingName("MapperWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}

// MARK: - URL Input Dialog

/// Dialog for entering a web URL to map to a key
struct URLInputDialog: View {
    @Binding var urlText: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Web URL")
                .font(.headline)

            TextField("example.com or https://...", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { onSubmit() }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("OK") {
                    onSubmit()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

// MARK: - Preview

#Preview {
    MapperView()
        .environmentObject(KanataViewModel(manager: RuntimeCoordinator()))
        .frame(height: 500)
}

import AppKit
import SwiftUI

// MARK: - View Model

@Observable
@MainActor
class InputCaptureViewModel {
    var capturedInputs: [CapturedInput] = []
    var isRecording = false

    private var eventMonitor: Any?

    func setupKeyCapture() {
        // Monitor will be started when recording begins
    }

    func startRecording() {
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Ignore if it's just a modifier key
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Command, Shift, etc.
            if modifierOnlyKeyCodes.contains(event.keyCode) {
                return event
            }

            let keyInput = CapturedInput.KeyInput(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers ?? "?",
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.capturedInputs.append(.key(keyInput))
                }
            }

            return nil // Consume the event
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func stopKeyCapture() {
        stopRecording()
    }

    func remove(_ input: CapturedInput) {
        capturedInputs.removeAll { $0.id == input.id }
    }

    func clearAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            capturedInputs.removeAll()
        }
    }

    func addApp(_ app: CapturedInput.AppInput) {
        capturedInputs.append(.app(app))
    }

    func addURL(_ url: URL) {
        let urlInput = CapturedInput.URLInput(
            url: url,
            title: url.lastPathComponent
        )
        capturedInputs.append(.url(urlInput))
    }

    func addSampleURL() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let urlInput = CapturedInput.URLInput(
                url: URL(string: "https://example.com")!,
                title: "example.com"
            )
            capturedInputs.append(.url(urlInput))
        }
    }
}

import Foundation

final class CLISpinner: @unchecked Sendable {
    private static let brailleFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let asciiFrames = ["-", "\\", "|", "/"]

    private let noColor: Bool
    private let isEnabled: Bool
    private var message: String
    private var timer: Timer?
    private var frameIndex = 0

    init(context: OutputContext) {
        noColor = context.noColor
        isEnabled = context.isInteractive && !context.quiet && !context.shouldOutputJSON
        message = ""
    }

    func start(_ message: String) {
        guard isEnabled else { return }
        self.message = message
        frameIndex = 0
        renderFrame()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func update(_ message: String) {
        self.message = message
    }

    func succeed(_ message: String) {
        guard isEnabled else { return }
        stop()
        let marker = ANSIColor.green("✓", noColor: noColor)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(marker) \(message)\n".utf8))
    }

    func fail(_ message: String) {
        guard isEnabled else { return }
        stop()
        let marker = ANSIColor.red("✗", noColor: noColor)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(marker) \(message)\n".utf8))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isEnabled {
            FileHandle.standardError.write(Data("\r\u{001b}[2K".utf8))
        }
    }

    private func tick() {
        frameIndex += 1
        renderFrame()
    }

    private func renderFrame() {
        let frames = noColor ? Self.asciiFrames : Self.brailleFrames
        let frame = frames[frameIndex % frames.count]
        let color = noColor ? frame : ANSIColor.yellow(frame, noColor: false)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(color) \(message)".utf8))
    }
}

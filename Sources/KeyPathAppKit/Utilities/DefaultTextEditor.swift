import AppKit
import UniformTypeIdentifiers

/// Opens a file in the user's default text editor, as `open -t` does, without
/// spawning a process.
enum DefaultTextEditor {
    enum Failure: Error { case noTextEditor }

    @MainActor
    static func open(_ path: String) async throws {
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
            throw Failure.noTextEditor
        }
        _ = try await NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: editor,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

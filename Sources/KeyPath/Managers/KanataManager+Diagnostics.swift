import Foundation

@MainActor
extension KanataManager {
    // MARK: - Diagnostics

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnostics.append(diagnostic)
        AppLogger.shared.log(
            "\(diagnostic.severity.emoji) [Diagnostic] \(diagnostic.title): \(diagnostic.description)")

        // Keep only last 50 diagnostics to prevent memory bloat
        if diagnostics.count > 50 {
            diagnostics.removeFirst(diagnostics.count - 50)
        }
    }
}


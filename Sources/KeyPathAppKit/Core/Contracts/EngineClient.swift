import Foundation

/// Transport-agnostic engine reload result.
enum EngineReloadResult {
    case success(response: String)
    case failure(error: String, response: String)
    case networkError(String)

    var isSuccess: Bool {
        switch self {
        case .success: true
        default: false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .failure(error, _): error
        case let .networkError(error): error
        case .success: nil
        }
    }

    var response: String? {
        switch self {
        case let .success(resp): resp
        case let .failure(_, resp): resp
        case .networkError: nil
        }
    }
}

/// Abstraction over the Kanata engine communication layer.
/// Implementations can use different transports (e.g., TCP, UDP) while exposing
/// a minimal, testable surface for the rest of the app.
protocol EngineClient: Sendable {
    /// Reload the current configuration in the engine.
    func reloadConfig() async -> EngineReloadResult
}

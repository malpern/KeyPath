import Foundation

/// Abstraction over the Kanata engine communication layer.
///
/// Implementations can use different transports (e.g., TCP, UDP) while exposing
/// a minimal, testable surface for the rest of the app.
protocol EngineClient {
    /// Reload the current configuration in the engine.
    /// Implementations should return a transport-specific result with
    /// success/error details.
    func reloadConfig() async -> TCPReloadResult
}



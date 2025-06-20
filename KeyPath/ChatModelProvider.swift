import Foundation

protocol ChatModelProvider {
    /// Sends a prompt to the model and returns the response asynchronously.
    func sendMessage(_ prompt: String) async throws -> String

    /// Streams a prompt to the model, providing partial updates as they arrive.
    /// - Parameters:
    ///   - prompt: The user prompt.
    ///   - onUpdate: Called with each partial response.
    func streamMessage(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws
}

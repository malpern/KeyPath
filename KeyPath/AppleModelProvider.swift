import Foundation
// import FoundationModels  // Not available in this environment

// Commented out until FoundationModels is available
/*
class AppleModelProvider: ChatModelProvider {
    private let systemInstructions: String
    private let temperature: Double

    private var session: LanguageModelSession?

    init(systemInstructions: String, temperature: Double) {
        self.systemInstructions = systemInstructions
        self.temperature = temperature
        self.session = LanguageModelSession(instructions: systemInstructions)
    }

    func sendMessage(_ prompt: String) async throws -> String {
        if session == nil {
            session = LanguageModelSession(instructions: systemInstructions)
        }
        let options = GenerationOptions(temperature: temperature)
        
        guard let currentSession = session else {
            throw NSError(domain: "AppleModelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session could not be created."])
        }
        
        let response = try await currentSession.respond(to: prompt, options: options)
        return response.content
    }

    func streamMessage(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        if session == nil {
            session = LanguageModelSession(instructions: systemInstructions)
        }
        let options = GenerationOptions(temperature: temperature)
        
        guard let currentSession = session else {
            throw NSError(domain: "AppleModelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session could not be created."])
        }
        
        let stream = currentSession.streamResponse(to: prompt, options: options)
        for try await partialResponse in stream {
            onUpdate(partialResponse)
        }
    }
}
*/

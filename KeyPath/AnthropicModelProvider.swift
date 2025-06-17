import Foundation

class AnthropicModelProvider: ChatModelProvider {
    private let apiKey: String
    private let model: String = "claude-3-5-sonnet-20241022"
    private let endpoint: String = "https://api.anthropic.com/v1/messages"
    private let temperature: Double
    private let systemInstructions: String
    
    init(systemInstructions: String, temperature: Double) {
        self.systemInstructions = systemInstructions
        self.temperature = temperature
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            fatalError("ANTHROPIC_API_KEY environment variable not set.")
        }
        self.apiKey = key
    }
    
    func sendMessage(_ prompt: String) async throws -> String {
        let request = try createRequest(prompt: prompt, streaming: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw Errors.unexpectedResponse(raw)
        }
        
        return text
    }
    
    func sendConversation(_ messages: [KeyPathMessage]) async throws -> String {
        let request = try createConversationRequest(messages: messages, streaming: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw Errors.unexpectedResponse(raw)
        }
        
        return text
    }
    
    func streamMessage(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        let request = try createRequest(prompt: prompt, streaming: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let handler = AnthropicSSEStreamHandler(
                onUpdate: onUpdate,
                completion: { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
            
            let session = URLSession(configuration: .default, delegate: handler, delegateQueue: nil)
            let task = session.dataTask(with: request)
            handler.task = task
            task.resume()
        }
    }
    
    private func createRequest(prompt: String, streaming: Bool) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw Errors.invalidURL
        }
        
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": temperature,
            "system": systemInstructions,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        if streaming {
            requestBody["stream"] = true
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
    
    private func createConversationRequest(messages: [KeyPathMessage], streaming: Bool) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw Errors.invalidURL
        }
        
        // Convert KeyPathMessage to Anthropic format
        var anthropicMessages: [[String: Any]] = []
        
        for message in messages {
            switch message.type {
            case .text(let text):
                anthropicMessages.append([
                    "role": message.role == .user ? "user" : "assistant",
                    "content": text
                ])
            case .rule(let rule):
                // Include the rule's kanata code and explanation in the conversation
                let ruleText = """
                I created this rule for you:
                
                **\(rule.explanation)**
                
                ```kanata
                \(rule.kanataRule)
                ```
                """
                anthropicMessages.append([
                    "role": "assistant",
                    "content": ruleText
                ])
            }
        }
        
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": temperature,
            "system": systemInstructions,
            "messages": anthropicMessages
        ]
        if streaming {
            requestBody["stream"] = true
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
    
    enum Errors: Error, LocalizedError {
        case invalidURL
        case noDataReceived
        case unexpectedResponse(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid endpoint URL."
            case .noDataReceived: "No data received."
            case .unexpectedResponse(let response): "Unexpected response: \(response)"
            }
        }
    }
}

class AnthropicSSEStreamHandler: NSObject, URLSessionDataDelegate {
    private let onUpdate: (String) -> Void
    private let completion: (Result<Void, Error>) -> Void
    var task: URLSessionDataTask?
    private var buffer = Data()
    private var isFinished = false
    
    init(onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.onUpdate = onUpdate
        self.completion = completion
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("[SSE] Received response headers.")
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[SSE] Error: Server returned non-2xx status code: \(statusCode)")
            let error = NSError(domain: "AnthropicSSEStreamHandler", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned non-2xx status code: \(statusCode)"])
            if !isFinished {
                isFinished = true
                self.completion(.failure(error))
            }
            completionHandler(.cancel)
            return
        }
        print("[SSE] Response OK (status code \(httpResponse.statusCode)). Allowing connection.")
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("[SSE] Received data chunk: \(String(data: data, encoding: .utf8) ?? "non-utf8 data")")
        buffer.append(data)
        processBuffer()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[SSE] Task completed with error: \(error.localizedDescription)")
        } else {
            print("[SSE] Task completed successfully.")
        }
        if isFinished { return }
        isFinished = true
        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }
    
    private func processBuffer() {
        print("[SSE] Processing buffer...")
        while let range = buffer.range(of: "\n\n".data(using: .utf8)!) {
            let eventData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let line = String(data: eventData, encoding: .utf8) {
                for eventLine in line.components(separatedBy: "\n") where eventLine.hasPrefix("data: ") {
                    let jsonString = String(eventLine.dropFirst(6))
                    if jsonString == "[DONE]" {
                        if !isFinished {
                            isFinished = true
                            completion(.success(()))
                            task?.cancel()
                        }
                        return
                    }
                    let jsonData = Data(jsonString.utf8)
                    if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let contentArr = json["delta"] as? [[String: Any]],
                       let text = contentArr.first?["text"] as? String {
                        onUpdate(text)
                    }
                }
            }
        }
    }
} 

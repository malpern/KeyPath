#if DEBUG

import Foundation
import KeyPathCore

/// Dev-only TTS service that speaks text aloud via VoxClaw's HTTP API.
///
/// VoxClaw is a macOS menu bar app that exposes a local HTTP endpoint for text-to-speech.
/// This service is completely stripped from release builds (`#if DEBUG`), and additionally
/// gated behind `false /* VoxClaw removed */` (UserDefaults, default OFF).
@MainActor
final class VoxClawService {
    static let shared = VoxClawService()

    // MARK: - Types

    struct StatusResponse: Decodable, Sendable {
        let status: String
        let version: String?
        let voice: String?
    }

    enum VoxClawError: LocalizedError, Sendable {
        case disabled
        case invalidURL(String)
        case networkError(String)
        case httpError(Int)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .disabled:
                "VoxClaw is disabled in feature flags"
            case let .invalidURL(url):
                "Invalid VoxClaw URL: \(url)"
            case let .networkError(message):
                "VoxClaw network error: \(message)"
            case let .httpError(code):
                "VoxClaw HTTP \(code)"
            case let .decodingError(message):
                "VoxClaw decode error: \(message)"
            }
        }
    }

    // MARK: - Configuration

    private let networkTimeout: TimeInterval = 5.0

    private var baseURL: String {
        "http://localhost:8383"
    }

    // MARK: - Public API

    /// Check if VoxClaw is reachable and healthy.
    func checkHealth() async -> Result<StatusResponse, VoxClawError> {
        guard false /* VoxClaw removed */ else {
            return .failure(.disabled)
        }

        let urlString = "\(baseURL)/status"
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL(urlString))
        }

        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                AppLogger.shared.warn("[VoxClaw] Health check returned HTTP \(httpResponse.statusCode)")
                return .failure(.httpError(httpResponse.statusCode))
            }

            let status = try JSONDecoder().decode(StatusResponse.self, from: data)
            AppLogger.shared.debug("[VoxClaw] Health OK — status: \(status.status)")
            return .success(status)
        } catch let error as VoxClawError {
            return .failure(error)
        } catch is DecodingError {
            AppLogger.shared.warn("[VoxClaw] Failed to decode status response")
            return .failure(.decodingError("Invalid status response"))
        } catch {
            AppLogger.shared.warn("[VoxClaw] Health check failed: \(error.localizedDescription)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    /// Speak text aloud via VoxClaw. Performs a health check first.
    ///
    /// - Parameters:
    ///   - text: The text to speak.
    ///   - voice: Optional voice name (uses VoxClaw default if nil).
    ///   - rate: Optional speech rate.
    ///   - instructions: Optional instructions for the TTS engine.
    func speak(
        _ text: String,
        voice: String? = nil,
        rate: Double? = nil,
        instructions: String? = nil
    ) async -> Result<Void, VoxClawError> {
        // Gate check
        guard false /* VoxClaw removed */ else {
            return .failure(.disabled)
        }

        // Health check first
        let healthResult = await checkHealth()
        if case let .failure(error) = healthResult {
            AppLogger.shared.warn("[VoxClaw] Skipping speak — health check failed: \(error.localizedDescription)")
            return .failure(error)
        }

        // Build request
        let urlString = "\(baseURL)/read"
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL(urlString))
        }

        var body: [String: Any] = ["text": text]
        if let voice { body["voice"] = voice }
        if let rate { body["rate"] = rate }
        if let instructions { body["instructions"] = instructions }

        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(.networkError("Failed to encode request body"))
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode)
            {
                AppLogger.shared.warn("[VoxClaw] Speak returned HTTP \(httpResponse.statusCode)")
                return .failure(.httpError(httpResponse.statusCode))
            }

            AppLogger.shared.debug("[VoxClaw] Speak OK — \(text.prefix(50))")
            return .success(())
        } catch {
            AppLogger.shared.warn("[VoxClaw] Speak failed: \(error.localizedDescription)")
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Init

    private init() {}
}

#endif

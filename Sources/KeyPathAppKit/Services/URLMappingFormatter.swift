import Foundation

/// Helpers for encoding/decoding URL payloads used in push-msg actions.
enum URLMappingFormatter {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Encode a URL so it is safe inside `open:` push-msg payloads.
    static func encodeForPushMessage(_ url: String) -> String {
        let decoded = url.removingPercentEncoding ?? url
        return decoded.addingPercentEncoding(withAllowedCharacters: unreserved) ?? decoded
    }

    /// Decode a URL payload from an `open:` push-msg string.
    static func decodeFromPushMessage(_ url: String) -> String {
        url.removingPercentEncoding ?? url
    }

    /// Format a URL for display (prefers host, strips scheme/path when possible).
    static func displayDomain(for url: String) -> String {
        let decoded = decodeFromPushMessage(url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return decoded }

        if let host = URL(string: decoded)?.host {
            return host
        }

        if let host = URL(string: "https://\(decoded)")?.host {
            return host
        }

        if let firstComponent = decoded.split(separator: "/").first {
            return String(firstComponent)
        }

        return decoded
    }
}

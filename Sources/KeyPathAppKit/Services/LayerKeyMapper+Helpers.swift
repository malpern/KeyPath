import Foundation
import KeyPathCore

extension LayerKeyMapper {
    // MARK: - Helpers

    /// Get hash of config file for cache invalidation
    func configFileHash(_ path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Simple hash based on file size and first/last bytes
        let size = data.count
        let first = data.first ?? 0
        let last = data.last ?? 0
        return "\(size)-\(first)-\(last)"
    }

    /// Extract URL from push-msg output if present
    /// Returns URL string if output contains "open:...", nil otherwise
    nonisolated func extractURLMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                // Direct match: "open:github.com" (from push-msg in simulator output)
                if candidate.lowercased().hasPrefix("open:") {
                    let url = String(candidate.dropFirst(5)) // Remove "open:"
                    let decoded = URLMappingFormatter.decodeFromPushMessage(url)
                    return decoded.isEmpty ? nil : decoded
                }

                // Also check for full push-msg format (in case simulator returns it verbatim)
                // Pattern: (push-msg "open:...")
                let pattern = #"push-msg\s+"open:([^"]+)""#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
                   let urlRange = Range(match.range(at: 1), in: candidate)
                {
                    let url = String(candidate[urlRange])
                    return URLMappingFormatter.decodeFromPushMessage(url)
                }
            }
        }
        return nil
    }

    /// Extract app identifier from push-msg output if present
    /// Returns app identifier string if output contains "launch:...", nil otherwise
    nonisolated func extractAppLaunchMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                if let action = extractKeyPathAction(from: candidate),
                   action.action.lowercased() == "launch",
                   let target = action.target
                {
                    return target
                }

                if candidate.lowercased().hasPrefix("launch:") {
                    let appId = String(candidate.dropFirst("launch:".count))
                    return appId.isEmpty ? nil : appId
                }
            }
        }
        return nil
    }

    /// Extract system action identifier from push-msg output if present
    /// Returns system action string if output contains "system:...", nil otherwise
    nonisolated func extractSystemActionMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                if let action = extractKeyPathAction(from: candidate),
                   action.action.lowercased() == "system",
                   let target = action.target
                {
                    return target
                }

                if candidate.lowercased().hasPrefix("system:") {
                    let actionId = String(candidate.dropFirst("system:".count))
                    return actionId.isEmpty ? nil : actionId
                }
            }
        }
        return nil
    }

    /// Extract the payload from push-msg outputs, returning candidates to inspect.
    nonisolated func pushMsgCandidates(from output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespaces)
        var candidates: [String] = [trimmed]

        let pattern = #"push-msg\s+"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let payloadRange = Range(match.range(at: 1), in: trimmed)
        {
            candidates.append(String(trimmed[payloadRange]))
        }

        return candidates
    }

    /// Extract a keypath:// action and target from a string (e.g., keypath://launch/Obsidian)
    nonisolated func extractKeyPathAction(from value: String) -> (action: String, target: String?)? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "keypath",
              let action = url.host, !action.isEmpty
        else {
            return nil
        }

        let rawPathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let target = rawPathComponents.first?.removingPercentEncoding ?? rawPathComponents.first
        return (action: action, target: target)
    }

    /// Human-readable label for system actions (matches overlay + mapper naming)
    nonisolated func systemActionDisplayLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            "Do Not Disturb"
        case "spotlight":
            "Spotlight"
        case "dictation":
            "Dictation"
        case "mission-control", "missioncontrol":
            "Mission Control"
        case "launchpad":
            "Launchpad"
        case "notification-center", "notificationcenter":
            "Notification Center"
        case "siri":
            "Siri"
        default:
            action.capitalized
        }
    }
}

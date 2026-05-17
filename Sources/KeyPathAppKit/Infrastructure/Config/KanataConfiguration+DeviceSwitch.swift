import Foundation

extension KanataConfiguration {
    /// Render a per-device switch expression for a key with device overrides.
    /// Returns the switch expression string (suitable for use inside an alias).
    ///
    /// - Parameters:
    ///   - defaultOutput: The output to use when no device-specific override matches.
    ///   - overrides: Per-device output overrides.
    ///   - connectedDevices: Currently connected devices (for hash→index resolution).
    ///   - inputKey: The original input key name (used when rendering behavior overrides).
    ///
    /// Device hashes are resolved to indices via the current connected device list.
    /// Unresolvable hashes (device not connected) are silently skipped.
    /// The default output is always emitted as the final fallthrough case.
    static func renderDeviceSwitchExpression(
        defaultOutput: String,
        overrides: [DeviceKeyOverride],
        connectedDevices: [ConnectedDevice],
        inputKey: String = ""
    ) -> String {
        let hashToIndex: [String: Int] = Dictionary(
            connectedDevices.enumerated().map { ($1.hash, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var cases: [String] = []
        for override in overrides {
            guard let index = hashToIndex[override.deviceHash] else { continue }
            let output: String
            if let behavior = override.behavior {
                let syntheticMapping = KeyMapping(
                    input: inputKey,
                    action: override.output,
                    behavior: behavior
                )
                output = KanataBehaviorRenderer.render(syntheticMapping, hyperLinkedLayerInfos: [])
            } else {
                output = override.output.kanataOutput
            }
            cases.append("((device \(index))) \(output) break")
        }

        // Default fallthrough case (always present)
        cases.append("() \(defaultOutput) break")

        return "(switch\n    " + cases.joined(separator: "\n    ") + ")"
    }

    /// Generate alias name for device switch expressions.
    /// Uses layer + sanitized input key. The input key is unique within a layer
    /// (Kanata enforces one output per source key per layer), so collisions
    /// from sanitization (e.g., "caps-lock" vs "caps lock") cannot occur in
    /// practice — the config generator deduplicates by source key before alias creation.
    static func deviceSwitchAliasName(for mapping: KeyMapping, layer: RuleCollectionLayer) -> String {
        let sanitized = sanitizeForAliasName(mapping.input)
        return "dev_\(layer.kanataName)_\(sanitized)"
    }

    /// Replace any character that isn't alphanumeric or underscore with `_`.
    private static func sanitizeForAliasName(_ input: String) -> String {
        String(input.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : Character("_") })
    }
}

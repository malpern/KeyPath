import Foundation

extension KanataConfiguration {
    /// Render a per-device switch expression for a key with device overrides.
    /// Returns the switch expression string (suitable for use inside an alias).
    ///
    /// Device hashes are resolved to indices via the current connected device list.
    /// Unresolvable hashes (device not connected) are silently skipped.
    /// The default output is always emitted as the final fallthrough case.
    static func renderDeviceSwitchExpression(
        defaultOutput: String,
        overrides: [DeviceKeyOverride],
        connectedDevices: [ConnectedDevice]
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
                // Render behavior using the behavior renderer with a synthetic mapping
                let syntheticMapping = KeyMapping(
                    input: "placeholder",
                    output: override.output,
                    behavior: behavior
                )
                output = KanataBehaviorRenderer.render(syntheticMapping, hyperLinkedLayerInfos: [])
            } else {
                output = KanataKeyConverter.convertToKanataSequence(override.output)
            }
            cases.append("((device \(index))) \(output) break")
        }

        // Default fallthrough case (always present)
        cases.append("() \(defaultOutput) break")

        return "(switch\n    " + cases.joined(separator: "\n    ") + ")"
    }

    /// Generate alias name for device switch expressions
    static func deviceSwitchAliasName(for mapping: KeyMapping, layer: RuleCollectionLayer) -> String {
        let sanitized = mapping.input
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "dev_\(layer.kanataName)_\(sanitized)"
    }
}

import Foundation
import KeyPathCore

/// Parses `kanata --list` output into structured device records.
/// Pure parsing logic kept separate from Process execution for testability.
enum DeviceEnumerationService {
    // MARK: - Parsing

    /// Parse ALL devices from `kanata --list` output into `[ConnectedDevice]`.
    /// Unlike `parseExcludedMacOSDeviceNames`, this returns every device (not just VirtualHID).
    static func parseAllDevices(fromKanataList output: String) -> [ConnectedDevice] {
        // Example lines (columns):
        // 0xHASH   vendor_id  product_id  product_key...
        let re = try? NSRegularExpression(pattern: #"^(0x[0-9A-Fa-f]+)\s+(\d+)\s+(\d+)\s+(.*)$"#)
        var seen = Set<String>()
        var devices: [ConnectedDevice] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let re else { continue }

            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = re.firstMatch(in: line, range: range), m.numberOfRanges >= 5 else { continue }

            let hash = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let vendorStr = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let productStr = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            let productKey = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)

            guard !hash.isEmpty, !seen.contains(hash) else { continue }
            seen.insert(hash)

            let vendorID = Int(vendorStr) ?? 0
            let productID = Int(productStr) ?? 0
            // Match both kanata's "VirtualHIDKeyboard" label and Karabiner's
            // broader "Karabiner-DriverKit-VirtualHIDDevice-*" product names.
            let isVirtualHID = productKey.contains("VirtualHIDKeyboard") || productKey.contains("VirtualHID")

            devices.append(ConnectedDevice(
                hash: hash,
                vendorID: vendorID,
                productID: productID,
                productKey: productKey,
                isVirtualHID: isVirtualHID
            ))
        }

        return devices
    }

    // MARK: - Dev Fake Devices

    #if DEBUG
        // DEV FALLBACK: macOS multi-device is blocked upstream (psych3r/driverkit#15).
        // These fake devices let the keyboard picker UI be tested with a single physical keyboard.
        // TODO: Remove once upstream lands. Tracked by #254.
        private static let devFakeDevices: [ConnectedDevice] = [
            ConnectedDevice(hash: "0xDEADBEEF", vendorID: 0x29EA, productID: 0x0041,
                            productKey: "Kinesis Advantage360 Pro", isVirtualHID: false),
            ConnectedDevice(hash: "0xCAFEBABE", vendorID: 0x1209, productID: 0x4173,
                            productKey: "ZSA Moonlander Mark I", isVirtualHID: false),
        ]
    #endif

    // MARK: - Enumeration

    #if os(macOS)
        /// Run `kanata --list` and return all connected devices.
        static func enumerateConnectedDevices() -> [ConnectedDevice] {
            let candidates = [
                "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata"
            ]

            let fm = Foundation.FileManager()
            guard let kanataPath = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
                AppLogger.shared.warn("⚠️ [DeviceEnumeration] No kanata binary found at known paths")
                #if DEBUG
                    let fallback = devFakeDevices
                    DeviceSelectionCache.shared.updateConnectedDevices(fallback)
                    return fallback
                #else
                    return []
                #endif
            }

            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: kanataPath)
                process.arguments = ["--list"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0,
                      let output = String(data: data, encoding: .utf8)
                else {
                    AppLogger.shared.warn("⚠️ [DeviceEnumeration] kanata --list exited with status \(process.terminationStatus)")
                    return []
                }

                var devices = parseAllDevices(fromKanataList: output)
                AppLogger.shared.log("🔌 [DeviceEnumeration] Found \(devices.count) device(s): \(devices.map(\.displayName).joined(separator: ", "))")

                #if DEBUG
                    // Supplement with fake devices when fewer than 2 physical keyboards detected
                    let physicalCount = devices.filter { !$0.isVirtualHID }.count
                    if physicalCount < 2 {
                        let fakes = devFakeDevices.filter { fake in
                            !devices.contains(where: { $0.hash == fake.hash })
                        }
                        devices.append(contentsOf: fakes)
                        AppLogger.shared.log("🔌 [DeviceEnumeration] Added \(fakes.count) fake device(s) for UI development")
                    }
                #endif

                // Cache for synchronous config generator reads
                DeviceSelectionCache.shared.updateConnectedDevices(devices)
                return devices
            } catch {
                AppLogger.shared.warn("⚠️ [DeviceEnumeration] Failed to run kanata --list: \(error)")
                return []
            }
        }
    #endif
}

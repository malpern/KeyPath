import Foundation
import KeyPathCore

/// Recognizes connected HID keyboards by matching their VID:PID against the QMK database.
///
/// Flow:
/// 1. Look up VID:PID in `QMKVIDPIDIndex`
/// 2. If multiple paths, rank: prefer those with built-in layout, then shortest path
/// 3. Get `KeyboardMetadata` from `QMKKeyboardDatabase`
/// 4. Resolve layout: built-in ID if available, else needs QMK import on user accept
actor DeviceRecognitionService {
    static let shared = DeviceRecognitionService()

    struct RecognitionResult: Sendable {
        let keyboardName: String
        let manufacturer: String?
        let layoutId: String?
        let qmkPath: String
        let isBuiltIn: Bool
        let needsImport: Bool
        let deviceEvent: HIDDeviceMonitor.HIDKeyboardEvent
    }

    func recognize(event: HIDDeviceMonitor.HIDKeyboardEvent) async -> RecognitionResult? {
        // Step 1: VID:PID lookup
        guard let match = QMKVIDPIDIndex.lookup(vendorID: event.vendorID, productID: event.productID) else {
            return nil
        }

        // Step 2: Rank paths — prefer built-in layouts, then shortest path
        let rankedPaths = rankPaths(match.keyboardPaths)
        guard let bestPath = rankedPaths.first else { return nil }

        // Step 3: Get metadata
        let metadata = await QMKKeyboardDatabase.shared.metadataForPath(bestPath)

        // Step 4: Resolve layout
        let builtInId = QMKKeyboardDatabase.qmkToBuiltInLayout[bestPath]
        let isBuiltIn = builtInId != nil

        return RecognitionResult(
            keyboardName: metadata?.name ?? event.productName,
            manufacturer: metadata?.manufacturer,
            layoutId: builtInId,
            qmkPath: bestPath,
            isBuiltIn: isBuiltIn,
            needsImport: !isBuiltIn,
            deviceEvent: event
        )
    }

    /// Rank QMK paths: built-in layouts first, then shortest path (most generic)
    private func rankPaths(_ paths: [String]) -> [String] {
        paths.sorted { a, b in
            let aBuiltIn = QMKKeyboardDatabase.qmkToBuiltInLayout[a] != nil
            let bBuiltIn = QMKKeyboardDatabase.qmkToBuiltInLayout[b] != nil

            if aBuiltIn != bBuiltIn { return aBuiltIn }
            return a.count < b.count
        }
    }
}

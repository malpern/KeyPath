import Foundation
import KeyPathCore

/// Recognizes connected HID keyboards by matching their VID:PID against the
/// normalized local keyboard detection index.
actor DeviceRecognitionService {
    static let shared = DeviceRecognitionService()

    struct RecognitionResult: Sendable {
        let keyboardName: String
        let manufacturer: String?
        let layoutId: String?
        let qmkPath: String?
        let isBuiltIn: Bool
        let needsImport: Bool
        let source: KeyboardDetectionIndex.Source
        let matchType: KeyboardDetectionIndex.MatchType
        let confidence: KeyboardDetectionIndex.Confidence
        let deviceEvent: HIDDeviceMonitor.HIDKeyboardEvent
    }

    func recognize(event: HIDDeviceMonitor.HIDKeyboardEvent) async -> RecognitionResult? {
        if let appleResult = AppleKeyboardRecognizer.recognize(event: event) {
            return appleResult
        }

        guard let match = KeyboardDetectionIndex.lookup(vendorID: event.vendorID, productID: event.productID) else {
            return nil
        }

        let record = match.record
        let shouldFetchMetadata = (record.displayName.isEmpty || record.manufacturer == nil) && record.qmkPath != nil
        let metadata: QMKKeyboardDatabase.KeyboardMeta? = if shouldFetchMetadata, let qmkPath = record.qmkPath {
            await QMKKeyboardDatabase.shared.metadataForPath(qmkPath)
        } else {
            nil
        }

        let builtInId = record.builtInLayoutId
            ?? record.qmkPath.flatMap { QMKKeyboardDatabase.qmkToBuiltInLayout[$0] }
        let isBuiltIn = builtInId != nil

        // Vendor-only fallbacks are only emitted when they safely collapse to
        // a single layout/import target. Any other ambiguous vendor-only match
        // is omitted by the generator and returns nil here.
        if !isBuiltIn, record.qmkPath == nil {
            return nil
        }

        return RecognitionResult(
            keyboardName: record.displayName.isEmpty ? (metadata?.name ?? event.productName) : record.displayName,
            manufacturer: record.manufacturer ?? metadata?.manufacturer,
            layoutId: builtInId,
            qmkPath: record.qmkPath,
            isBuiltIn: isBuiltIn,
            needsImport: !isBuiltIn,
            source: record.source,
            matchType: record.matchType,
            confidence: record.confidence,
            deviceEvent: event
        )
    }
}

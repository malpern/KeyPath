import Foundation

enum AppleKeyboardRecognizer {
    private static let appleVendorID = 0x05AC

    static func recognize(event: HIDDeviceMonitor.HIDKeyboardEvent) -> DeviceRecognitionService.RecognitionResult? {
        let lowerName = event.productName.lowercased()
        let isInternalKeyboard = lowerName.contains("internal keyboard")
        let isAppleVendor = event.vendorID == appleVendorID

        guard isAppleVendor || isInternalKeyboard else { return nil }

        if isInternalKeyboard {
            return DeviceRecognitionService.RecognitionResult(
                keyboardName: "MacBook Keyboard",
                manufacturer: "Apple",
                layoutId: KeyboardTypeDetector.recommendedLayoutId(),
                qmkPath: nil,
                isBuiltIn: true,
                needsImport: false,
                source: .override,
                matchType: .exactVIDPID,
                confidence: .high,
                deviceEvent: event
            )
        }

        if let magicKeyboard = recognizeMagicKeyboard(event: event, lowerName: lowerName) {
            return magicKeyboard
        }

        return nil
    }

    private static func recognizeMagicKeyboard(
        event: HIDDeviceMonitor.HIDKeyboardEvent,
        lowerName: String
    ) -> DeviceRecognitionService.RecognitionResult? {
        let productID = event.productID

        let compactProductIDs: Set<Int> = [0x0267, 0x029C]
        let compactTouchIDProductIDs: Set<Int> = [0x029A]
        let numpadProductIDs: Set<Int> = [0x026C]
        let numpadTouchIDProductIDs: Set<Int> = [0x029F]

        let hasTouchID = lowerName.contains("touch id") || compactTouchIDProductIDs.contains(productID) || numpadTouchIDProductIDs.contains(productID)
        let hasNumericKeypad = lowerName.contains("numeric keypad") || numpadProductIDs.contains(productID) || numpadTouchIDProductIDs.contains(productID)

        let layoutId: String
        let keyboardName: String

        switch (hasTouchID, hasNumericKeypad) {
        case (true, true):
            layoutId = "magic-keyboard-touchid-numpad"
            keyboardName = "Magic Keyboard with Touch ID and Numeric Keypad"
        case (true, false):
            layoutId = "magic-keyboard-touchid"
            keyboardName = "Magic Keyboard with Touch ID"
        case (false, true):
            layoutId = "magic-keyboard-numpad"
            keyboardName = "Magic Keyboard with Numeric Keypad"
        case (false, false):
            guard lowerName.contains("magic keyboard") || compactProductIDs.contains(productID) else {
                return nil
            }
            layoutId = "magic-keyboard-compact"
            keyboardName = "Magic Keyboard"
        }

        return DeviceRecognitionService.RecognitionResult(
            keyboardName: keyboardName,
            manufacturer: "Apple",
            layoutId: layoutId,
            qmkPath: nil,
            isBuiltIn: true,
            needsImport: false,
            source: .override,
            matchType: .exactVIDPID,
            confidence: .high,
            deviceEvent: event
        )
    }
}

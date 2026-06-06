import Foundation
import IOKit
import IOKit.hid
import KeyPathCore
import Observation

/// Monitors USB HID keyboard connect/disconnect events via IOKit.
///
/// Publishes `connectedKeyboards` as keyboards are plugged in and removed.
/// Filters out VirtualHID devices and devices with VID:PID 0:0 (BLE with no identity).
///
/// ## Thread safety
///
/// This class is `@MainActor` for its published UI state. IOKit callbacks arrive on a
/// dedicated `Thread` (not GCD — GCD can reclaim threads, killing the run loop).
/// The boundary works as follows:
///
/// - `monitorThread`, `trackedDeviceIDs`, `connectedKeyboards`, `lastConnectedKeyboard`
///   are MainActor-isolated and only accessed from MainActor code.
/// - `_monitorRunLoop` is shared between MainActor (`stopMonitoring`) and the IOKit
///   thread (`setupHIDManager`). Access is serialized by `runLoopLock`.
///   `CFRunLoopStop` is documented as cross-thread safe.
/// - `setupHIDManager` runs entirely on the IOKit thread. Its local `manager` stays
///   alive while `CFRunLoopRun()` blocks.
/// - `handleDeviceConnected`/`handleDeviceRemoved` run on the IOKit thread, extract
///   Sendable data, then hop to MainActor via `Task { @MainActor }`.
@Observable
@MainActor
final class HIDDeviceMonitor {
    static let shared = HIDDeviceMonitor()

    struct HIDKeyboardEvent: Sendable, Equatable, Identifiable {
        let vendorID: Int
        let productID: Int
        let productName: String
        let isConnected: Bool

        var id: String {
            "\(vendorID):\(productID):\(productName)"
        }

        var vidPidKey: String {
            String(format: "%04X:%04X", vendorID, productID)
        }
    }

    private(set) var connectedKeyboards: [HIDKeyboardEvent] = []

    private(set) var lastConnectedKeyboard: HIDKeyboardEvent?

    /// Dedicated thread for the IOKit run loop. Non-nil means monitoring is active.
    /// Only accessed from MainActor (startMonitoring/stopMonitoring).
    private var monitorThread: Thread?

    /// Protects `_monitorRunLoop` across the MainActor ↔ IOKit thread boundary.
    /// CFRunLoop is not Sendable so we can't use Mutex/OSAllocatedUnfairLock.
    private let runLoopLock = NSLock()
    /// The IOKit thread's CFRunLoop. Written by the IOKit thread in setupHIDManager,
    /// read by MainActor in stopMonitoring. All access is under `runLoopLock`.
    private nonisolated(unsafe) var _monitorRunLoop: CFRunLoop?

    private var trackedDeviceIDs: [UInt: HIDKeyboardEvent] = [:]

    static func currentKeyboardSnapshot() -> [HIDKeyboardEvent] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.compactMap { device in
            let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown Keyboard"

            let lowerName = productName.lowercased()
            let isAppleInternalKeyboard = lowerName.contains("apple internal keyboard")

            guard vendorID != 0 || productID != 0 || isAppleInternalKeyboard else { return nil }
            guard !productName.contains("VirtualHID") else { return nil }

            return HIDKeyboardEvent(
                vendorID: vendorID,
                productID: productID,
                productName: productName,
                isConnected: true
            )
        }
        .sorted { lhs, rhs in
            if lhs.vendorID != rhs.vendorID {
                return lhs.vendorID < rhs.vendorID
            }
            if lhs.productID != rhs.productID {
                return lhs.productID < rhs.productID
            }
            return lhs.productName < rhs.productName
        }
    }

    func startMonitoring() {
        guard monitorThread == nil else { return }

        let thread = Thread { [weak self] in
            self?.setupHIDManager()
        }
        thread.name = "com.keypath.hid-monitor"
        thread.qualityOfService = .utility
        monitorThread = thread
        thread.start()

        AppLogger.shared.log("🔌 [HIDDeviceMonitor] Started monitoring keyboard connections")
    }

    func stopMonitoring() {
        guard monitorThread != nil else { return }

        runLoopLock.lock()
        let runLoop = _monitorRunLoop
        runLoopLock.unlock()
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        monitorThread = nil

        AppLogger.shared.log("🔌 [HIDDeviceMonitor] Stopped monitoring keyboard connections")
    }

    // MARK: - IOKit Setup (runs entirely on the dedicated IOKit thread)

    private nonisolated func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // SAFETY: passUnretained is safe because HIDDeviceMonitor is a singleton
        // (static let shared) — it is never deallocated during app lifetime.
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleDeviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleDeviceRemoved(device)
        }, context)

        let runLoop = CFRunLoopGetCurrent()!
        runLoopLock.lock()
        _monitorRunLoop = runLoop
        runLoopLock.unlock()

        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Blocks until CFRunLoopStop is called from stopMonitoring.
        // The local `manager` stays alive on the stack for the duration.
        CFRunLoopRun()

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        runLoopLock.lock()
        _monitorRunLoop = nil
        runLoopLock.unlock()
    }

    // MARK: - Device Callbacks (called on IOKit thread, hop to MainActor)

    private nonisolated func handleDeviceConnected(_ device: IOHIDDevice) {
        guard let event = extractEvent(from: device, isConnected: true) else { return }
        let deviceID = UInt(bitPattern: ObjectIdentifier(device))

        Task { @MainActor [weak self] in
            guard let self else { return }
            trackedDeviceIDs[deviceID] = event

            if !connectedKeyboards.contains(where: { $0.id == event.id }) {
                connectedKeyboards.append(event)
                lastConnectedKeyboard = event
                AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard connected: \(event.productName) (\(event.vidPidKey))")
                NotificationCenter.default.post(name: .hidKeyboardConnected, object: nil, userInfo: ["event": event])
            }
        }
    }

    private nonisolated func handleDeviceRemoved(_ device: IOHIDDevice) {
        let deviceID = UInt(bitPattern: ObjectIdentifier(device))

        Task { @MainActor [weak self] in
            guard let self, let event = trackedDeviceIDs.removeValue(forKey: deviceID) else { return }
            connectedKeyboards.removeAll { $0.id == event.id }
            AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard disconnected: \(event.productName) (\(event.vidPidKey))")
            NotificationCenter.default.post(name: .hidKeyboardDisconnected, object: nil, userInfo: ["event": event])
        }
    }

    // MARK: - Device Info Extraction (called on IOKit thread, returns Sendable value)

    private nonisolated func extractEvent(from device: IOHIDDevice, isConnected: Bool) -> HIDKeyboardEvent? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown Keyboard"

        let lowerName = productName.lowercased()
        let isAppleInternalKeyboard = lowerName.contains("apple internal keyboard")

        guard vendorID != 0 || productID != 0 || isAppleInternalKeyboard else { return nil }
        guard !productName.contains("VirtualHID") else { return nil }

        return HIDKeyboardEvent(
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            isConnected: isConnected
        )
    }
}

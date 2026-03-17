import Foundation
import IOKit
import IOKit.hid
import KeyPathCore

/// Monitors USB HID keyboard connect/disconnect events via IOKit.
///
/// Publishes `connectedKeyboards` as keyboards are plugged in and removed.
/// Filters out VirtualHID devices and devices with VID:PID 0:0 (BLE with no identity).
@MainActor
final class HIDDeviceMonitor: ObservableObject {
    static let shared = HIDDeviceMonitor()

    struct HIDKeyboardEvent: Sendable, Equatable, Identifiable {
        let vendorID: Int
        let productID: Int
        let productName: String
        let isConnected: Bool

        var id: String {
            "\(vendorID):\(productID):\(productName)"
        }

        /// Formatted VID:PID key for index lookup, e.g. "4653:0001"
        var vidPidKey: String {
            String(format: "%04X:%04X", vendorID, productID)
        }
    }

    @Published private(set) var connectedKeyboards: [HIDKeyboardEvent] = []

    /// The most recently connected keyboard (for toast display)
    @Published private(set) var lastConnectedKeyboard: HIDKeyboardEvent?

    private var isMonitoring = false

    /// Dedicated thread for the IOKit run loop — GCD queues can reclaim threads,
    /// which would silently kill the run loop and stop all IOKit callbacks.
    private nonisolated(unsafe) var monitorThread: Thread?
    /// Guard for `_monitorRunLoop` — CFRunLoop is not Sendable so we can't use Mutex/OSAllocatedUnfairLock.
    /// Safety: only accessed under `runLoopLock`; CFRunLoopStop is cross-thread safe per Apple docs.
    private let runLoopLock = NSLock()
    private nonisolated(unsafe) var _monitorRunLoop: CFRunLoop?
    private nonisolated(unsafe) var hidManager: IOHIDManager?

    /// Track devices by opaque pointer value (avoids sending IOHIDDevice across isolation)
    private var trackedDeviceIDs: [UInt: HIDKeyboardEvent] = [:]

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

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
        guard isMonitoring else { return }
        isMonitoring = false

        runLoopLock.lock()
        let runLoop = _monitorRunLoop
        runLoopLock.unlock()
        if let runLoop {
            CFRunLoopStop(runLoop) // Cross-thread safe per Apple docs
        }
        monitorThread = nil

        AppLogger.shared.log("🔌 [HIDDeviceMonitor] Stopped monitoring keyboard connections")
    }

    // MARK: - IOKit Setup

    private nonisolated func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match keyboard devices
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Register callbacks
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

        // Store references before entering the run loop
        let runLoop = CFRunLoopGetCurrent()!
        runLoopLock.lock()
        _monitorRunLoop = runLoop
        runLoopLock.unlock()
        hidManager = manager

        // Schedule on the dedicated thread's run loop
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Run the run loop to receive callbacks (blocks until CFRunLoopStop)
        CFRunLoopRun()

        // Cleanup after run loop stops
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        runLoopLock.lock()
        _monitorRunLoop = nil
        runLoopLock.unlock()
        hidManager = nil
    }

    // MARK: - Device Callbacks

    private nonisolated func handleDeviceConnected(_ device: IOHIDDevice) {
        // Extract all data from IOHIDDevice on the callback thread (before crossing isolation)
        guard let event = extractEvent(from: device, isConnected: true) else { return }
        let deviceID = UInt(bitPattern: ObjectIdentifier(device))

        Task { @MainActor [weak self] in
            guard let self else { return }
            trackedDeviceIDs[deviceID] = event

            // Avoid duplicates
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

    // MARK: - Device Info Extraction

    private nonisolated func extractEvent(from device: IOHIDDevice, isConnected: Bool) -> HIDKeyboardEvent? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown Keyboard"

        // Filter out VID:PID 0:0 (BLE devices with no USB identity)
        guard vendorID != 0 || productID != 0 else { return nil }

        // Filter out VirtualHID devices
        guard !productName.contains("VirtualHID") else { return nil }

        return HIDKeyboardEvent(
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            isConnected: isConnected
        )
    }
}

import Foundation
import IOKit
import IOKit.hid
import KeyPathCore
import Observation

/// Monitors keyboard connect/disconnect events via I/O Registry notifications.
/// Needs no privacy permission: it reads registry properties and never opens a device.
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
    @ObservationIgnored
    private nonisolated(unsafe) var _monitorRunLoop: CFRunLoop?

    private var trackedDeviceIDs: [UInt64: HIDKeyboardEvent] = [:]

    static func currentKeyboardSnapshot() -> [HIDKeyboardEvent] {
        RegistryKeyboards.current().compactMap { event(from: $0, isConnected: true) }
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

    /// Watches the I/O Registry for keyboards arriving and leaving. Reading a
    /// registry entry needs no privacy permission, unlike opening the device
    /// through IOHIDManager, which requires Input Monitoring.
    private nonisolated func setupHIDManager() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var addedIterator: io_iterator_t = 0
        var removedIterator: io_iterator_t = 0

        IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, RegistryKeyboards.hidDeviceMatching(),
            { context, iterator in
                guard let context else { return }
                Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                    .handleDevicesConnected(RegistryKeyboards.drain(iterator))
            }, context, &addedIterator
        )
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, RegistryKeyboards.hidDeviceMatching(),
            { context, iterator in
                guard let context else { return }
                Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                    .handleDevicesRemoved(RegistryKeyboards.drainIDs(iterator))
            }, context, &removedIterator
        )
        // Arm both notifications and report the keyboards already present.
        handleDevicesConnected(RegistryKeyboards.drain(addedIterator))
        _ = RegistryKeyboards.drainIDs(removedIterator)

        let runLoop = CFRunLoopGetCurrent()!
        runLoopLock.lock()
        _monitorRunLoop = runLoop
        runLoopLock.unlock()

        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(runLoop, source, .defaultMode)

        // Blocks until CFRunLoopStop is called from stopMonitoring.
        CFRunLoopRun()

        CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        IOObjectRelease(addedIterator)
        IOObjectRelease(removedIterator)
        IONotificationPortDestroy(port)
        runLoopLock.lock()
        _monitorRunLoop = nil
        runLoopLock.unlock()
    }

    // MARK: - Device Callbacks (called on IOKit thread, hop to MainActor)

    private nonisolated func handleDevicesConnected(_ entries: [RegistryKeyboards.Entry]) {
        let events = entries.compactMap { entry in
            Self.event(from: entry, isConnected: true).map { (entry.registryID, $0) }
        }
        guard !events.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for (deviceID, event) in events {
                trackedDeviceIDs[deviceID] = event
                if !connectedKeyboards.contains(where: { $0.id == event.id }) {
                    connectedKeyboards.append(event)
                    lastConnectedKeyboard = event
                    AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard connected: \(event.productName) (\(event.vidPidKey))")
                    NotificationCenter.default.post(name: .hidKeyboardConnected, object: nil, userInfo: ["event": event])
                }
            }
        }
    }

    private nonisolated func handleDevicesRemoved(_ deviceIDs: [UInt64]) {
        guard !deviceIDs.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for deviceID in deviceIDs {
                guard let event = trackedDeviceIDs.removeValue(forKey: deviceID) else { continue }
                // A keyboard can expose several HID interfaces with the same identity.
                guard !trackedDeviceIDs.values.contains(where: { $0.id == event.id }) else { continue }
                connectedKeyboards.removeAll { $0.id == event.id }
                AppLogger.shared.log("🔌 [HIDDeviceMonitor] Keyboard disconnected: \(event.productName) (\(event.vidPidKey))")
                NotificationCenter.default.post(name: .hidKeyboardDisconnected, object: nil, userInfo: ["event": event])
            }
        }
    }

    // MARK: - Device Info Extraction

    nonisolated static func event(from entry: RegistryKeyboards.Entry, isConnected: Bool) -> HIDKeyboardEvent? {
        let isAppleInternalKeyboard = entry.productName.lowercased().contains("apple internal keyboard")
        guard entry.vendorID != 0 || entry.productID != 0 || isAppleInternalKeyboard else { return nil }
        guard !entry.productName.contains("VirtualHID") else { return nil }
        return HIDKeyboardEvent(
            vendorID: entry.vendorID,
            productID: entry.productID,
            productName: entry.productName,
            isConnected: isConnected
        )
    }
}

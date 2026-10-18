import Foundation
import IOKit.hidsystem

/// Caps Lock is a system latch, not a synthesized key held in the output ledger.
/// Read the live state for each new press so another keyboard can change it.
final class SessionCapsLockOutput {
    enum Failure: Error { case connection, read(Int32), write(Int32), verification, invalidValue }
    private var pressed = false
    private let toggle: () throws -> Void

    init(toggle: @escaping () throws -> Void = SessionCapsLockOutput.toggleNativeState) {
        self.toggle = toggle
    }

    func receive(value: UInt64) throws {
        guard value <= 2 else { throw Failure.invalidValue }
        if value == 0 { pressed = false; return }
        guard value == 1, !pressed else { return }
        try toggle()
        pressed = true
    }

    static func toggleNativeState() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { throw Failure.connection }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else {
            throw Failure.connection
        }
        defer { IOServiceClose(connection) }
        var state = false
        let read = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state)
        guard read == KERN_SUCCESS else { throw Failure.read(read) }
        let target = !state
        let write = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), target)
        guard write == KERN_SUCCESS else { throw Failure.write(write) }
        // IOHIDSystem publishes the updated lock state asynchronously. In the
        // VM, enabling Caps Lock was observable through event flags before this
        // getter caught up. Bound verification so a real failure still stops
        // output, without rejecting an accepted change on its first read.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.02
        repeat {
            let verify = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state)
            guard verify == KERN_SUCCESS else { throw Failure.read(verify) }
            if state == target { return }
            Thread.sleep(forTimeInterval: 0.001)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw Failure.verification
    }
}

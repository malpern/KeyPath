import Foundation
import KeyPathCore

/// Consent belongs to one event-service instance in one boot. It is never a
/// reconnect locator or permission to substitute another keyboard.
struct SessionCapsSelection: Codable, Sendable, Equatable {
    let version: Int
    let bootSessionUUID: String
    let device: SessionCapsMappingPolicy.DeviceIdentity
    let reservesF18: Bool

    init(device: SessionCapsMappingPolicy.DeviceIdentity, bootSessionUUID: String, reservesF18: Bool) {
        version = 1
        self.device = device
        self.bootSessionUUID = bootSessionUUID
        self.reservesF18 = reservesF18
    }

    func approvedDevice(currentBoot: String) throws -> SessionCapsMappingPolicy.DeviceIdentity {
        guard version == 1, reservesF18,
              let approvedBoot = UUID(uuidString: bootSessionUUID),
              approvedBoot == UUID(uuidString: currentBoot) else { throw SessionCapsRuntimeSupport.Refusal.selection }
        _ = try SessionCapsHIDUtilTransport.selector(device)
        return device
    }

    func verifyConnected(devices: [SessionCapsMappingPolicy.DeviceIdentity], currentBoot: String) throws {
        guard devices == [try approvedDevice(currentBoot: currentBoot)] else {
            throw SessionCapsRuntimeSupport.Refusal.selection
        }
    }

    static func decode(_ data: Data, currentBoot: String) throws -> Self {
        guard data.count <= 4096,
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == Set(["version", "bootSessionUUID", "device", "reservesF18"]),
              let device = fields["device"] as? [String: Any],
              Set(device.keys).isSuperset(of: ["registryEntryID", "vendorID", "productID"]),
              Set(device.keys).isSubset(of: ["registryEntryID", "vendorID", "productID", "serialNumber", "locationID"]) else {
            throw SessionCapsRuntimeSupport.Refusal.selection
        }
        let selection = try JSONDecoder().decode(Self.self, from: data)
        _ = try selection.approvedDevice(currentBoot: currentBoot)
        return selection
    }
}

@MainActor
enum SessionCapsSelectionStore {
    static func save(_ selection: SessionCapsSelection?) throws {
        if let selection {
            let data = try JSONEncoder().encode(selection)
            _ = try SessionCapsSelection.decode(data, currentBoot: SessionCapsRuntimeSupport.bootSessionUUID())
            UserDefaults.standard.set(data, forKey: SessionCapsRuntimeSupport.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionCapsRuntimeSupport.selectionKey)
        }
    }
}

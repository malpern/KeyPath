import KeyPathCore
import SwiftUI

/// Connected keyboard information. Driverless remapping applies to all keyboards;
/// per-device exclusions require device identity that the session event stream lacks.
struct DeviceSelectionView: View {
    @State private var connectedDevices: [ConnectedDevice]
    @State private var isLoading: Bool
    private let providedDevices: [ConnectedDevice]?

    init(devices: [ConnectedDevice]? = nil) {
        providedDevices = devices
        _connectedDevices = State(initialValue: devices ?? [])
        _isLoading = State(initialValue: devices == nil)
    }

    private var physicalConnected: [ConnectedDevice] {
        connectedDevices.filter { !$0.isNonKeyboard }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Connected Keyboards")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if physicalConnected.isEmpty {
                            Text("No keyboards detected. Check your keyboard connection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(physicalConnected) { device in
                            HStack(spacing: 10) {
                                Image(systemName: device.sfSymbolName)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(device.vendorProductHex)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("connected-keyboard-\(device.hash)")
                        }
                    }
                }
                Text("Remapping applies to all connected keyboards. Choosing which keyboards to remap is not supported in driverless mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("devices-driverless-info")
            }
        }
        .padding(.top, 4)
        .task {
            guard providedDevices == nil else { return }
            connectedDevices = await Task.detached(priority: .userInitiated) {
                DeviceEnumerationService.enumerateConnectedDevices()
            }.value
            isLoading = false
        }
    }
}

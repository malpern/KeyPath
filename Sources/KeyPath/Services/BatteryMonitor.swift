#if os(macOS)

    import Foundation
    import IOKit.ps

    /// Snapshot of the current battery status
    struct BatteryReading: Equatable, Sendable {
        let level: Double
        let isCharging: Bool
        let timestamp: Date
    }

    /// Abstraction for retrieving battery information
    protocol BatteryStatusProviding {
        func currentStatus() -> BatteryReading?
    }

    /// Default implementation backed by IOKit power source APIs
    struct IOKitBatteryStatusProvider: BatteryStatusProviding {
        func currentStatus() -> BatteryReading? {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
                return nil
            }

            guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef], !list.isEmpty else {
                return nil
            }

            for item in list {
                guard
                    let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue()
                    as? [String: Any]
                else { continue }

                let currentCapacityValue = description[kIOPSCurrentCapacityKey as String]
                let maxCapacityValue = description[kIOPSMaxCapacityKey as String]

                let currentCapacity = (currentCapacityValue as? Double)
                    ?? (currentCapacityValue as? NSNumber)?.doubleValue
                let maxCapacity = (maxCapacityValue as? Double)
                    ?? (maxCapacityValue as? NSNumber)?.doubleValue

                guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { continue }

                let normalizedLevel = max(0.0, min(1.0, currentCapacity / maxCapacity))

                let isCharging: Bool = if let chargingFlag = description[kIOPSIsChargingKey as String] as? Bool {
                    chargingFlag
                } else if let powerState = description[kIOPSPowerSourceStateKey as String] as? String {
                    powerState == kIOPSACPowerValue
                } else {
                    false
                }

                return BatteryReading(level: normalizedLevel, isCharging: isCharging, timestamp: Date())
            }

            return nil
        }
    }

    /// Polls the system battery and dispatches updates to the provided handler
    final class BatteryMonitor: @unchecked Sendable {
        typealias Handler = @Sendable (BatteryReading?) -> Void

        private let provider: BatteryStatusProviding
        private let pollInterval: TimeInterval
        private var task: Task<Void, Never>?

        init(pollInterval: TimeInterval = 30.0, provider: BatteryStatusProviding = IOKitBatteryStatusProvider()) {
            self.pollInterval = pollInterval
            self.provider = provider
        }

        func start(handler: @escaping Handler) {
            stop()

            task = Task.detached(priority: .background) { [pollInterval, provider] in
                while !Task.isCancelled {
                    handler(provider.currentStatus())

                    let interval = max(pollInterval, 1.0)
                    do {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        break
                    }
                }
            }
        }

        func stop() {
            task?.cancel()
            task = nil
        }

        deinit {
            stop()
        }
    }

#endif

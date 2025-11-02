import ApplicationServices
import Foundation
import IOKit.hidsystem
import Network
import SwiftUI

// MARK: - KanataManager Output Extension

extension KanataManager {
    // MARK: - Log Monitoring

    /// Start monitoring Kanata logs for VirtualHID connection failures
    func startLogMonitoring() {
        // Cancel any existing monitoring
        logMonitorTask?.cancel()

        logMonitorTask = Task.detached { [weak self] in
            guard let self else { return }

            let logPath = "/var/log/kanata.log"
            guard FileManager.default.fileExists(atPath: logPath) else {
                AppLogger.shared.log("⚠️ [LogMonitor] Kanata log file not found at \(logPath)")
                return
            }

            AppLogger.shared.log("🔍 [LogMonitor] Starting real-time VirtualHID connection monitoring")

            // Monitor log file for connection failures
            var lastPosition: UInt64 = 0

            while !Task.isCancelled {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logPath))
                    defer { fileHandle.closeFile() }

                    let fileSize = fileHandle.seekToEndOfFile()
                    if fileSize > lastPosition {
                        fileHandle.seek(toFileOffset: lastPosition)
                        let newData = fileHandle.readDataToEndOfFile()
                        lastPosition = fileSize

                        if let logContent = String(data: newData, encoding: .utf8) {
                            await self.analyzeLogContent(logContent)
                        }
                    }

                    // Check every 2 seconds
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    AppLogger.shared.log("⚠️ [LogMonitor] Error reading log file: \(error)")
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // Wait 5 seconds before retry
                }
            }

            AppLogger.shared.log("🔍 [LogMonitor] Stopped log monitoring")
        }
    }

    /// Stop log monitoring
    func stopLogMonitoring() {
        logMonitorTask?.cancel()
        logMonitorTask = nil
        Task { await healthMonitor.recordConnectionSuccess() } // Reset on stop
    }
}

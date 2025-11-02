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
        diagnosticsManager.startLogMonitoring()
    }

    /// Stop log monitoring
    func stopLogMonitoring() {
        diagnosticsManager.stopLogMonitoring()
    }
}

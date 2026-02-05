import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Freshness Guard

    func isFresh(_ result: SystemStateResult) -> Bool {
        snapshotAge(result) <= 3.0
    }

    func snapshotAge(_ result: SystemStateResult) -> TimeInterval {
        Date().timeIntervalSince(result.detectionTimestamp)
    }

}

import Foundation
import SwiftUI

/// Simple environment object to let child pages trigger a wizard refresh with optional force flag.
final class WizardRefreshProxy: ObservableObject {
    var refreshHandler: (_ force: Bool) -> Void = { _ in }

    func refresh(force: Bool) {
        refreshHandler(force)
    }
}

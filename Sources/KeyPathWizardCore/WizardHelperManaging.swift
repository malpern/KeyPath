import Foundation
import KeyPathCore

// MARK: - WizardHelperManaging Protocol

/// Protocol abstracting HelperManager for use by the wizard module.
/// Covers only the methods that wizard files actually call.
public protocol WizardHelperManaging: AnyObject, Sendable {
    func isHelperInstalled() async -> Bool
    func testHelperFunctionality() async -> Bool
    func getHelperVersion() async -> String?
    func helperNeedsLoginItemsApproval() -> Bool
}

// MARK: - WizardHelperConstants

/// Constants from HelperManager that wizard files reference.
public enum WizardHelperConstants {
    public static let helperPlistName = "com.keypath.helper.plist"
    public static let helperMachServiceName = "com.keypath.helper"
    public static let helperBundleIdentifier = "com.keypath.helper"
}

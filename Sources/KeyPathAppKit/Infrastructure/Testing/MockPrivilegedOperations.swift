import Foundation

/// Test double for PrivilegedOperations used during tests to avoid admin prompts
public struct MockPrivilegedOperations: PrivilegedOperations {
  public init() {}

  public func startKanataService() async -> Bool { true }
  public func restartKanataService() async -> Bool { true }
  public func stopKanataService() async -> Bool { true }
}

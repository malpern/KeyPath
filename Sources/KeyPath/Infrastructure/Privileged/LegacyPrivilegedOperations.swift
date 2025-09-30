import Foundation

/// Errors that can occur during privileged operations
///
/// - Deprecated: Use `KeyPathError.permission(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.permission(...) instead")
enum PrivilegedOperationError: Error {
    case timeout
    case executionFailed(String?)

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case .timeout:
            return .permission(.privilegedOperationFailed(operation: "privileged operation", reason: "Operation timed out"))
        case let .executionFailed(message):
            let reason = message ?? "Execution failed"
            return .permission(.privilegedOperationFailed(operation: "privileged operation", reason: reason))
        }
    }
}

/// Legacy implementation that performs privileged operations by invoking AppleScript
/// with administrator privileges and shelling out to launchctl.
///
/// Behavior matches existing flows but centralizes them behind one abstraction.
public struct LegacyPrivilegedOperations: PrivilegedOperations {
    public init() {}

    public func startKanataService() async -> Bool {
        let script = """
        tell application "System Events"
            try
                set the result to (do shell script "launchctl kickstart system/com.keypath.kanata" with administrator privileges)
                return true
            on error
                return false
            end try
        end tell
        """
        return await executeAppleScript(script)
    }

    public func restartKanataService() async -> Bool {
        let script = """
        tell application "System Events"
            try
                set the result to (do shell script "launchctl kickstart -k system/com.keypath.kanata" with administrator privileges)
                return true
            on error
                return false
            end try
        end tell
        """
        return await executeAppleScript(script)
    }

    public func stopKanataService() async -> Bool {
        let script = """
        tell application "System Events"
            try
                set the result to (do shell script "launchctl kill TERM system/com.keypath.kanata" with administrator privileges)
                return true
            on error
                return false
            end try
        end tell
        """
        return await executeAppleScript(script)
    }

    private func executeAppleScript(_ source: String) async -> Bool {
        AppLogger.shared.log("🔧 [PrivilegedOps] Executing AppleScript with 15-second timeout...")
        
        do {
            let success = try await withTimeout(seconds: 15.0) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let appleScript = NSAppleScript(source: source)
                        var errorDict: NSDictionary?
                        _ = appleScript?.executeAndReturnError(&errorDict)
                        
                        let success = errorDict == nil
                        if !success, let error = errorDict {
                            AppLogger.shared.log("❌ [PrivilegedOps] AppleScript error: \(error)")
                        }
                        
                        continuation.resume(returning: success)
                    }
                }
            }
            
            AppLogger.shared.log("✅ [PrivilegedOps] AppleScript completed successfully")
            return success
            
        } catch {
            AppLogger.shared.log("⚠️ [PrivilegedOps] AppleScript timed out or failed: \(error)")
            return false
        }
    }
    
    /// Timeout wrapper for async operations
    private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PrivilegedOperationError.timeout
            }
            
            guard let result = try await group.next() else {
                throw PrivilegedOperationError.timeout
            }
            
            group.cancelAll()
            return result
        }
    }
}



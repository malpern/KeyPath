import Foundation
import ServiceManagement
import os.log
import SwiftUI

class PrivilegedHelperManager: ObservableObject {
    static let shared = PrivilegedHelperManager()
    
    private let helperIdentifier = "com.keypath.KeyPath.helper"
    private let log = OSLog(subsystem: "com.keypath.app", category: "helper")
    
    private var xpcConnection: NSXPCConnection?
    
    private init() {}
    
    // MARK: - Helper Installation
    
    private func cleanupOldServices() async {
        AppLogger.shared.log("🧹 [HelperManager] Cleaning up old KeyPath services...")
        
        // List of old service identifiers to clean up
        let oldServiceIdentifiers = [
            "com.keypath.helper",
            "com.keypath.kanata",
            "com.keypath.kanata.helper",
            "com.keypath.kanata.helper.v2",
            "com.keypath.kanata.helper.v4",
            "com.keypath.kanata.xpc",
            "com.keypath.helperpoc.helper"
        ]
        
        if #available(macOS 13.0, *) {
            for identifier in oldServiceIdentifiers {
                // Skip our current identifier
                if identifier == helperIdentifier {
                    continue
                }
                
                let oldService = SMAppService.daemon(plistName: "\(identifier).plist")
                if oldService.status == .enabled {
                    do {
                        AppLogger.shared.log("🧹 [HelperManager] Attempting to unregister old service: \(identifier)")
                        try await oldService.unregister()
                        AppLogger.shared.log("✅ [HelperManager] Successfully unregistered: \(identifier)")
                    } catch {
                        AppLogger.shared.log("⚠️ [HelperManager] Failed to unregister \(identifier): \(error)")
                    }
                }
            }
        }
        
        // Also clean up any old plist files
        let fileManager = FileManager.default
        let launchDaemonsPath = "/Library/LaunchDaemons"
        
        for identifier in oldServiceIdentifiers {
            let plistPath = "\(launchDaemonsPath)/\(identifier).plist"
            if fileManager.fileExists(atPath: plistPath) {
                AppLogger.shared.log("🧹 [HelperManager] Found old plist at: \(plistPath) (requires manual removal)")
            }
        }
    }
    
    func installHelper() async -> Bool {
        AppLogger.shared.log("🔧 [HelperManager] Starting helper installation...")
        
        // Clean up old services first
        await cleanupOldServices()
        
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            AppLogger.shared.log("🔧 [HelperManager] Created SMAppService with plist: \(helperIdentifier).plist")
            do {
                AppLogger.shared.log("🔧 [HelperManager] Calling service.register()...")
                try await service.register()
                AppLogger.shared.log("✅ [HelperManager] Successfully registered privileged helper via SMAppService")
                os_log("Successfully registered privileged helper via SMAppService", log: log, type: .info)
                return true
            } catch {
                AppLogger.shared.log("❌ [HelperManager] SMAppService registration failed: \(error)")
                AppLogger.shared.log("❌ [HelperManager] Error details: \(error.localizedDescription)")
                os_log("Failed to register helper via SMAppService: %@", log: log, type: .error, error.localizedDescription)
                return false
            }
        } else {
            // Fallback for older macOS versions using SMJobBless
            return await withCheckedContinuation { continuation in
                var authRef: AuthorizationRef?
                let status = AuthorizationCreate(nil, nil, [], &authRef)
                
                guard status == errAuthorizationSuccess, let authRef = authRef else {
                    os_log("Failed to create authorization reference", log: log, type: .error)
                    continuation.resume(returning: false)
                    return
                }
                
                defer {
                    AuthorizationFree(authRef, [])
                }
                
                var error: Unmanaged<CFError>?
                if SMJobBless(kSMDomainSystemLaunchd, helperIdentifier as CFString, authRef, &error) {
                    os_log("Successfully installed privileged helper via SMJobBless", log: log, type: .info)
                    continuation.resume(returning: true)
                } else {
                    if let error = error?.takeRetainedValue() {
                        os_log("Failed to install helper via SMJobBless: %@", log: log, type: .error, error.localizedDescription)
                    } else {
                        os_log("Failed to install helper via SMJobBless: unknown error", log: log, type: .error)
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func isHelperInstalled() -> Bool {
        AppLogger.shared.log("🔍 [HelperManager] Checking if helper is installed...")
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            let status = service.status
            let isInstalled = status == .enabled
            AppLogger.shared.log("🔍 [HelperManager] SMAppService status: \(status), isInstalled: \(isInstalled)")
            return isInstalled
        } else {
            // Fallback for older macOS versions using SMJobBless
            let job = SMJobCopyDictionary(kSMDomainSystemLaunchd, helperIdentifier as CFString)
            if let jobDict = job?.takeRetainedValue() as? [String: Any], !jobDict.isEmpty {
                os_log("Helper is installed (SMJobBless)", log: log, type: .info)
                return true
            } else {
                os_log("Helper is not installed (SMJobBless)", log: log, type: .info)
                return false
            }
        }
    }
    
    func uninstallHelper() async -> Bool {
        AppLogger.shared.log("🗑️ [HelperManager] Starting helper uninstallation...")
        
        // Stop Kanata first
        _ = await stopKanata()
        
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            do {
                try await service.unregister()
                AppLogger.shared.log("✅ [HelperManager] Successfully unregistered helper")
                
                // Clean up old services too
                await cleanupOldServices()
                
                return true
            } catch {
                AppLogger.shared.log("❌ [HelperManager] Failed to unregister helper: \(error)")
                return false
            }
        } else {
            // For older macOS versions, SMJobRemove requires authorization
            var authRef: AuthorizationRef?
            let status = AuthorizationCreate(nil, nil, [], &authRef)
            
            guard status == errAuthorizationSuccess, let authRef = authRef else {
                return false
            }
            
            defer {
                AuthorizationFree(authRef, [])
            }
            
            var error: Unmanaged<CFError>?
            let result = SMJobRemove(kSMDomainSystemLaunchd, helperIdentifier as CFString, authRef, true, &error)
            
            if !result, let error = error?.takeRetainedValue() {
                AppLogger.shared.log("❌ [HelperManager] Failed to remove helper: \(error)")
            }
            
            return result
        }
    }
    
    // MARK: - XPC Connection
    
    private func getXPCConnection() -> NSXPCConnection {
        if let connection = xpcConnection {
            return connection
        }
        
        let connection = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: KeyPathHelperProtocol.self)
        
        connection.invalidationHandler = {
            os_log("XPC connection invalidated", log: self.log, type: .info)
            self.xpcConnection = nil
        }
        
        connection.interruptionHandler = {
            os_log("XPC connection interrupted", log: self.log, type: .info)
            self.xpcConnection = nil
        }
        
        connection.resume()
        xpcConnection = connection
        
        return connection
    }
    
    // MARK: - Helper Communication

    func startKanata() async -> (Bool, String?) {
        return await withCheckedContinuation { continuation in
            let helper = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: (false, "XPC connection error: \(error.localizedDescription)"))
            } as? KeyPathHelperProtocol
            
            helper?.startKanata(withReply: { success, error in
                continuation.resume(returning: (success, error))
            })
        }
    }

    func stopKanata() async -> (Bool, String?) {
        return await withCheckedContinuation { continuation in
            let helper = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: (false, "XPC connection error: \(error.localizedDescription)"))
            } as? KeyPathHelperProtocol
            
            helper?.stopKanata(withReply: { success, error in
                continuation.resume(returning: (success, error))
            })
        }
    }
    
    func reloadKanataConfig(configPath: String) async -> (Bool, String?) {
        return await withCheckedContinuation { continuation in
            let connection = getXPCConnection()
            let helper = connection.remoteObjectProxyWithErrorHandler { error in
                os_log("XPC error: %@", log: self.log, type: .error, error.localizedDescription)
                continuation.resume(returning: (false, "XPC connection error: \(error.localizedDescription)"))
            } as? KeyPathHelperProtocol
            
            helper?.reloadKanataConfig(configPath: configPath) { success, error in
                continuation.resume(returning: (success, error))
            }
        }
    }
    
    func restartKanataService() async -> (Bool, String?) {
        return await startKanata()
    }
    
    func getHelperVersion() async -> String? {
        return await withCheckedContinuation { continuation in
            let connection = getXPCConnection()
            let helper = connection.remoteObjectProxyWithErrorHandler { error in
                os_log("XPC error: %@", log: self.log, type: .error, error.localizedDescription)
                continuation.resume(returning: nil)
            } as? KeyPathHelperProtocol
            
            helper?.getHelperVersion { version in
                continuation.resume(returning: version)
            }
        }
    }
    
    // MARK: - Cleanup
    
    func disconnect() {
        xpcConnection?.invalidate()
        xpcConnection = nil
    }
}

import Foundation
import os.log

// MARK: - Helper Tool Main Entry Point

class KeyPathHelper: NSObject, KeyPathHelperProtocol {
    
    private let log = OSLog(subsystem: "com.keypath.helper", category: "main")
    private var kanataProcess: Process?

    // This handler will be set by the ServiceDelegate to clean up the process
    // when the XPC connection is invalidated.
    var onInvalidate: (() -> Void)?

    override init() {
        super.init()
        // Set up the invalidation handler to call our cleanup method.
        self.onInvalidate = { [weak self] in
            self?.stopKanata(withReply: { _, _ in })
        }
    }
    
    func startKanata(withReply reply: @escaping (Bool, String?) -> Void) {
        os_log("Received request to start Kanata", log: log, type: .info)

        // If a process is already running, stop it first.
        if let existingProcess = kanataProcess, existingProcess.isRunning {
            os_log("Kanata process already running (PID: %d). Terminating it before starting a new one.", log: log, type: .info, existingProcess.processIdentifier)
            existingProcess.terminate()
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/kanata-cmd")
        
        // Use a default config path. The main app is responsible for ensuring it exists.
        let configPath = "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
        task.arguments = ["--cfg", configPath]
        
        do {
            try task.run()
            self.kanataProcess = task
            os_log("Successfully started Kanata process (PID: %d)", log: log, type: .info, task.processIdentifier)
            reply(true, nil)
        } catch {
            os_log("Failed to start Kanata: %@", log: log, type: .error, error.localizedDescription)
            reply(false, "Failed to start Kanata: \(error.localizedDescription)")
        }
    }

    func stopKanata(withReply reply: @escaping (Bool, String?) -> Void) {
        os_log("Received request to stop Kanata", log: log, type: .info)
        
        guard let process = self.kanataProcess, process.isRunning else {
            os_log("No running Kanata process to stop.", log: log, type: .info)
            reply(true, "No process was running.")
            return
        }
        
        os_log("Terminating Kanata process (PID: %d)", log: log, type: .info, process.processIdentifier)
        process.terminate()
        self.kanataProcess = nil
        reply(true, nil)
    }

    // The old methods are kept for compatibility but now just call the new ones.
    func reloadKanataConfig(configPath: String, withReply reply: @escaping (Bool, String?) -> Void) {
        os_log("Reloading Kanata config by restarting the process.", log: log, type: .info)
        // To "reload", we just restart the process.
        startKanata(withReply: reply)
    }
    
    func restartKanataService(withReply reply: @escaping (Bool, String?) -> Void) {
        os_log("Restarting Kanata service.", log: log, type: .info)
        startKanata(withReply: reply)
    }
    
    func getHelperVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.1.0") // Bump version to reflect new functionality
    }
}

// MARK: - XPC Service Setup

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    private let log = OSLog(subsystem: "com.keypath.helper", category: "xpc")
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        os_log("Received new XPC connection", log: log, type: .info)
        
        let helper = KeyPathHelper()
        newConnection.exportedInterface = NSXPCInterface(with: KeyPathHelperProtocol.self)
        newConnection.exportedObject = helper
        
        // This is the crucial part. When the connection from the main app is
        // invalidated (e.g., the app quits or crashes), this handler is called.
        newConnection.invalidationHandler = {
            os_log("XPC connection invalidated. Cleaning up Kanata process.", log: self.log, type: .info)
            // Call the cleanup handler we defined in the helper.
            helper.onInvalidate?()
        }
        
        newConnection.interruptionHandler = {
            os_log("XPC connection interrupted.", log: self.log, type: .info)
        }
        
        newConnection.resume()
        
        return true
    }
}

// MARK: - Main

// The helper is now purely event-driven based on XPC calls from the main app.
// We no longer need to auto-start anything when the helper itself launches.
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate

os_log("KeyPath Helper starting and waiting for connections...", type: .info)
listener.resume()

// Keep the service running to listen for connections.
RunLoop.main.run()
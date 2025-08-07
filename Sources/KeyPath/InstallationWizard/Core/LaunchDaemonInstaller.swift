import Foundation

/// Manages LaunchDaemon installation and configuration for KeyPath services
/// Implements the production-ready LaunchDaemon architecture identified in the installer improvement analysis
class LaunchDaemonInstaller {
  // MARK: - Dependencies

  private let packageManager: PackageManager

  // MARK: - Constants

  private static let launchDaemonsPath = "/Library/LaunchDaemons"
  private static let kanataServiceID = "com.keypath.kanata"
  private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
  private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

  // Static paths for components that don't vary by system
  private static let kanataConfigPath = "/usr/local/etc/kanata/keypath.kbd"
  private static let vhidDaemonPath =
    "/Library/Application Support/org.pqrs/Karabiner-VirtualHIDDevice/bin/karabiner_vhid_daemon"
  private static let vhidManagerPath =
    "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

  // MARK: - Initialization

  init(packageManager: PackageManager = PackageManager()) {
    self.packageManager = packageManager
  }

  // MARK: - Path Detection Methods

  /// Gets the detected Kanata binary path or returns fallback
  private func getKanataBinaryPath() -> String {
    // Unify on a single canonical binary path to align permissions and UI guidance
    let standardPath = WizardSystemPaths.kanataActiveBinary
    AppLogger.shared.log("✅ [LaunchDaemon] Using canonical Kanata path: \(standardPath)")
    return standardPath
  }

  // MARK: - Installation Methods

  /// Creates and installs all LaunchDaemon services with a single admin prompt
  func createAllLaunchDaemonServices() -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Creating all LaunchDaemon services")

    let kanataBinaryPath = getKanataBinaryPath()

    // Generate all plist contents
    let kanataPlist = generateKanataPlist(binaryPath: kanataBinaryPath)
    let vhidDaemonPlist = generateVHIDDaemonPlist()
    let vhidManagerPlist = generateVHIDManagerPlist()

    // Create temporary files for all plists
    let tempDir = NSTemporaryDirectory()
    let kanataTempPath = "\(tempDir)\(Self.kanataServiceID).plist"
    let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
    let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

    do {
      // Write all plist contents to temporary files
      try kanataPlist.write(toFile: kanataTempPath, atomically: true, encoding: .utf8)
      try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
      try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

      // Install all services with a single admin prompt
      let success = executeAllWithAdminPrivileges(
        kanataTemp: kanataTempPath,
        vhidDaemonTemp: vhidDaemonTempPath,
        vhidManagerTemp: vhidManagerTempPath
      )

      // Clean up temporary files
      try? FileManager.default.removeItem(atPath: kanataTempPath)
      try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
      try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

      return success
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
      return false
    }
  }

  /// Creates and installs the Kanata LaunchDaemon service
  func createKanataLaunchDaemon() -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Creating Kanata LaunchDaemon service")

    let kanataBinaryPath = getKanataBinaryPath()
    let plistContent = generateKanataPlist(binaryPath: kanataBinaryPath)
    let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"

    return installPlist(content: plistContent, path: plistPath, serviceID: Self.kanataServiceID)
  }

  /// Creates and installs the VirtualHIDDevice Daemon LaunchDaemon service
  func createVHIDDaemonService() -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Daemon LaunchDaemon service")

    let plistContent = generateVHIDDaemonPlist()
    let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"

    return installPlist(content: plistContent, path: plistPath, serviceID: Self.vhidDaemonServiceID)
  }

  /// Creates and installs the VirtualHIDDevice Manager LaunchDaemon service
  func createVHIDManagerService() -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Manager LaunchDaemon service")

    let plistContent = generateVHIDManagerPlist()
    let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

    return installPlist(
      content: plistContent, path: plistPath, serviceID: Self.vhidManagerServiceID
    )
  }

  /// Loads all KeyPath LaunchDaemon services
  func loadServices() async -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Loading all KeyPath LaunchDaemon services")

    let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
    var allSucceeded = true

    for serviceID in services {
      let success = await loadService(serviceID: serviceID)
      if !success {
        allSucceeded = false
        AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service: \(serviceID)")
      }
    }

    return allSucceeded
  }

  // MARK: - Service Management

  /// Loads a specific LaunchDaemon service
  private func loadService(serviceID: String) async -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Loading service: \(serviceID)")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["load", "-w", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus == 0 {
        AppLogger.shared.log("✅ [LaunchDaemon] Successfully loaded service: \(serviceID)")
        return true
      } else {
        AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service \(serviceID): \(output)")
        return false
      }
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Error loading service \(serviceID): \(error)")
      return false
    }
  }

  /// Unloads a specific LaunchDaemon service
  private func unloadService(serviceID: String) async -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Unloading service: \(serviceID)")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["unload", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus == 0 {
        AppLogger.shared.log("✅ [LaunchDaemon] Successfully unloaded service: \(serviceID)")
        return true
      } else {
        AppLogger.shared.log(
          "⚠️ [LaunchDaemon] Service \(serviceID) may not have been loaded: \(output)")
        return true  // Not an error if it wasn't loaded
      }
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Error unloading service \(serviceID): \(error)")
      return false
    }
  }

  /// Checks if a LaunchDaemon service is currently loaded
  func isServiceLoaded(serviceID: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["list", serviceID]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let isLoaded = task.terminationStatus == 0
      AppLogger.shared.log("🔍 [LaunchDaemon] Service \(serviceID) loaded: \(isLoaded)")
      return isLoaded
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Error checking service \(serviceID): \(error)")
      return false
    }
  }

  // MARK: - Plist Generation

  private func generateKanataPlist(binaryPath: String) -> String {
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(Self.kanataServiceID)</string>
          <key>ProgramArguments</key>
          <array>
              <string>\(binaryPath)</string>
              <string>--cfg</string>
              <string>\(Self.kanataConfigPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/var/log/kanata.log</string>
          <key>StandardErrorPath</key>
          <string>/var/log/kanata.log</string>
          <key>UserName</key>
          <string>root</string>
          <key>GroupName</key>
          <string>wheel</string>
          <key>ThrottleInterval</key>
          <integer>10</integer>
      </dict>
      </plist>
      """
  }

  private func generateVHIDDaemonPlist() -> String {
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(Self.vhidDaemonServiceID)</string>
          <key>ProgramArguments</key>
          <array>
              <string>\(Self.vhidDaemonPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/var/log/karabiner-vhid-daemon.log</string>
          <key>StandardErrorPath</key>
          <string>/var/log/karabiner-vhid-daemon.log</string>
          <key>UserName</key>
          <string>root</string>
          <key>GroupName</key>
          <string>wheel</string>
          <key>ThrottleInterval</key>
          <integer>10</integer>
      </dict>
      </plist>
      """
  }

  private func generateVHIDManagerPlist() -> String {
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(Self.vhidManagerServiceID)</string>
          <key>ProgramArguments</key>
          <array>
              <string>\(Self.vhidManagerPath)</string>
              <string>activate</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>StandardOutPath</key>
          <string>/var/log/karabiner-vhid-manager.log</string>
          <key>StandardErrorPath</key>
          <string>/var/log/karabiner-vhid-manager.log</string>
          <key>UserName</key>
          <string>root</string>
          <key>GroupName</key>
          <string>wheel</string>
      </dict>
      </plist>
      """
  }

  // MARK: - File System Operations

  private func installPlist(content: String, path: String, serviceID: String) -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Installing plist: \(path)")

    // Create temporary file with plist content
    let tempDir = NSTemporaryDirectory()
    let tempPath = "\(tempDir)\(serviceID).plist"

    do {
      // Write content to temporary file first
      try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

      // Use admin privileges to install the plist
      let success = executeWithAdminPrivileges(
        tempPath: tempPath,
        finalPath: path,
        serviceID: serviceID
      )

      // Clean up temporary file
      try? FileManager.default.removeItem(atPath: tempPath)

      return success
    } catch {
      AppLogger.shared.log(
        "❌ [LaunchDaemon] Failed to create temporary plist \(serviceID): \(error)")
      return false
    }
  }

  /// Execute all LaunchDaemon installations with a single administrator privileges request
  private func executeAllWithAdminPrivileges(
    kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
  ) -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install all services")

    let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
    let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
    let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

    // Create a single compound command that installs all three services
    let command = """
      mkdir -p '\(Self.launchDaemonsPath)' && \
      cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)' && \
      cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)' && \
      cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'
      """

    // Use osascript to request admin privileges with proper password dialog
    let osascriptCommand = """
      do shell script "\(command)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
      """

    let osascriptTask = Process()
    osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osascriptTask.arguments = ["-e", osascriptCommand]

    let pipe = Pipe()
    osascriptTask.standardOutput = pipe
    osascriptTask.standardError = pipe

    do {
      try osascriptTask.run()
      osascriptTask.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if osascriptTask.terminationStatus == 0 {
        AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed all LaunchDaemon services")
        return true
      } else {
        AppLogger.shared.log("❌ [LaunchDaemon] Failed to install services: \(output)")
        return false
      }
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute admin command: \(error)")
      return false
    }
  }

  /// Execute LaunchDaemon installation with administrator privileges using osascript
  private func executeWithAdminPrivileges(tempPath: String, finalPath: String, serviceID: String)
    -> Bool
  {
    AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install \(serviceID)")

    // Create the command to copy the file and set proper permissions
    let command =
      "mkdir -p '\(Self.launchDaemonsPath)' && cp '\(tempPath)' '\(finalPath)' && chown root:wheel '\(finalPath)' && chmod 644 '\(finalPath)'"

    // Use osascript to request admin privileges with proper password dialog
    let osascriptCommand = """
      do shell script "\(command)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
      """

    let osascriptTask = Process()
    osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osascriptTask.arguments = ["-e", osascriptCommand]

    let pipe = Pipe()
    osascriptTask.standardOutput = pipe
    osascriptTask.standardError = pipe

    do {
      try osascriptTask.run()
      osascriptTask.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if osascriptTask.terminationStatus == 0 {
        AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed plist: \(serviceID)")
        return true
      } else {
        AppLogger.shared.log("❌ [LaunchDaemon] Failed to install plist \(serviceID): \(output)")
        return false
      }
    } catch {
      AppLogger.shared.log(
        "❌ [LaunchDaemon] Failed to execute admin command for \(serviceID): \(error)")
      return false
    }
  }

  // MARK: - Cleanup Methods

  /// Removes all KeyPath LaunchDaemon services
  func removeAllServices() async -> Bool {
    AppLogger.shared.log("🔧 [LaunchDaemon] Removing all KeyPath LaunchDaemon services")

    let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
    var allSucceeded = true

    for serviceID in services {
      // First unload the service
      let unloadSuccess = await unloadService(serviceID: serviceID)

      // Then remove the plist file
      let plistPath = "\(Self.launchDaemonsPath)/\(serviceID).plist"
      let removeSuccess = removePlist(path: plistPath, serviceID: serviceID)

      if !unloadSuccess || !removeSuccess {
        allSucceeded = false
      }
    }

    return allSucceeded
  }

  private func removePlist(path: String, serviceID: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    task.arguments = ["sudo", "-n", "rm", "-f", path]

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus == 0 {
        AppLogger.shared.log("✅ [LaunchDaemon] Successfully removed plist: \(serviceID)")
        return true
      } else {
        AppLogger.shared.log("❌ [LaunchDaemon] Failed to remove plist: \(serviceID)")
        return false
      }
    } catch {
      AppLogger.shared.log("❌ [LaunchDaemon] Error removing plist \(serviceID): \(error)")
      return false
    }
  }

  // MARK: - Status Methods

  /// Gets comprehensive status of all LaunchDaemon services
  func getServiceStatus() -> LaunchDaemonStatus {
    let kanataLoaded = isServiceLoaded(serviceID: Self.kanataServiceID)
    let vhidDaemonLoaded = isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
    let vhidManagerLoaded = isServiceLoaded(serviceID: Self.vhidManagerServiceID)

    return LaunchDaemonStatus(
      kanataServiceLoaded: kanataLoaded,
      vhidDaemonServiceLoaded: vhidDaemonLoaded,
      vhidManagerServiceLoaded: vhidManagerLoaded
    )
  }
}

// MARK: - Supporting Types

/// Status information for LaunchDaemon services
struct LaunchDaemonStatus {
  let kanataServiceLoaded: Bool
  let vhidDaemonServiceLoaded: Bool
  let vhidManagerServiceLoaded: Bool

  /// True if all required services are loaded
  var allServicesLoaded: Bool {
    kanataServiceLoaded && vhidDaemonServiceLoaded && vhidManagerServiceLoaded
  }

  /// Description of current status for logging/debugging
  var description: String {
    """
    LaunchDaemon Status:
    - Kanata Service: \(kanataServiceLoaded)
    - VHIDDevice Daemon: \(vhidDaemonServiceLoaded)
    - VHIDDevice Manager: \(vhidManagerServiceLoaded)
    - All Services Loaded: \(allServicesLoaded)
    """
  }
}

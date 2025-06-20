import Foundation

class KanataSetupChecker {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default
    
    func checkKanataSetup() -> Result<Bool, KanataValidationError> {
        let configDir = (configPath as NSString).deletingLastPathComponent

        // Create config directory if it doesn't exist
        if !fileManager.fileExists(atPath: configDir) {
            do {
                try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
                print("Created Kanata config directory: \(configDir)")
            } catch {
                return .failure(.configDirectoryNotFound)
            }
        }

        // Create config file if it doesn't exist
        if !fileManager.fileExists(atPath: configPath) {
            let defaultConfig = """
            ;; KeyPath Generated Kanata Configuration
            ;; This file was automatically created by KeyPath

            (defcfg
              process-unmapped-keys yes
            )

            (defsrc
              ;; Default source layout - will be updated by KeyPath rules
              caps
            )

            (deflayer default
              ;; Default layer - will be updated by KeyPath rules
              caps
            )

            ;; KeyPath rules will be added below
            """

            do {
                try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
                print("Created default Kanata config: \(configPath)")
            } catch {
                return .failure(.configFileNotFound)
            }
        }

        return .success(true)
    }
}
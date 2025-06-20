import Foundation

class KanataExecutableFinder {
    private let fileManager = FileManager.default
    
    func findKanataPath() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/kanata",
            "/usr/local/bin/kanata",
            "/usr/bin/kanata"
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                print("Kanata found at: \(path)")
                return path
            }
        }

        // Try using which command as fallback
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    print("Kanata found via which: \(path)")
                    return path
                }
            }
        } catch {
            print("Failed to run which command: \(error)")
        }

        return nil
    }
    
    func isHomebrewInstalled() -> Bool {
        let commonBrewPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in commonBrewPaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }
    
    func isKarabinerRunning() -> Bool {
        print("🔧 DEBUG: Skipping Karabiner check for testing")
        // TODO: Re-enable Karabiner conflict detection after testing
        // For now, allow KeyPath to work even with Karabiner running
        return false
    }
}
import Foundation

class KanataInstaller {
    private let executableFinder = KanataExecutableFinder()
    private let validator = KanataConfigValidator()
    private let serviceManager = KanataServiceManager()
    private let setupChecker = KanataSetupChecker()

    // Auto-install Kanata using Homebrew
    func autoInstallKanata(completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["brew", "install", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { process in
            if process.terminationStatus == 0 {
                completion(.success(true))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                completion(.failure(.kanataInstallationFailed(output)))
            }
        }

        do {
            try task.run()
        } catch {
            completion(.failure(.kanataInstallationFailed("Failed to run brew command: \(error.localizedDescription)")))
        }
    }

    // Check if Homebrew is installed
    func isHomebrewInstalled() -> Bool {
        return executableFinder.isHomebrewInstalled()
    }

    // Check if Karabiner-Elements is running
    func isKarabinerRunning() -> Bool {
        return executableFinder.isKarabinerRunning()
    }

    // Legacy support - map old InstallError to new KanataValidationError
    typealias InstallError = KanataValidationError

    // Check if Kanata is installed and config exists (create if needed)
    func checkKanataSetup() -> Result<Bool, KanataValidationError> {
        return setupChecker.checkKanataSetup()
    }

    // Validate a rule using kanata --check and semantic validation
    func validateRule(_ rule: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        validator.validateRule(rule, completion: completion)
    }

    // Install a validated rule
    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, KanataValidationError>) -> Void) {
        serviceManager.installRule(rule, completion: completion)
    }

    // Get current config for display
    func getCurrentConfig() -> String? {
        return serviceManager.getCurrentConfig()
    }

    // Undo last rule by restoring from backup
    func undoLastRule(backupPath: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        serviceManager.undoLastRule(backupPath: backupPath, completion: completion)
    }
}

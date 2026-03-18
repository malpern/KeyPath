import Foundation

enum LayoutAnalysisRunner {
    struct Result {
        let outputURL: URL
        let data: Data
    }

    static func analyze(imageURL: URL, yoloModel: String = "") throws -> Result {
        let scriptURL = try analyzerScriptURL()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-layout-analysis-\(UUID().uuidString).json")
        let pythonURL = preferredPythonURL()

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            scriptURL.path,
            "--image", imageURL.path,
            "--output", outputURL.path,
        ] + (yoloModel.isEmpty ? [] : ["--yolo-model", yoloModel])

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "KeyPathLayoutTracer.Analysis",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText?.isEmpty == false ? errorText! : "Keyboard analysis failed."]
            )
        }

        let data = try Data(contentsOf: outputURL)
        return Result(outputURL: outputURL, data: data)
    }

    private static func analyzerScriptURL() throws -> URL {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("Scripts/analyze_keyboard_image.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NSError(
                domain: "KeyPathLayoutTracer.Analysis",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Analyzer script not found at \(scriptURL.path)"]
            )
        }
        return scriptURL
    }

    private static func preferredPythonURL() -> URL {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let venvPython = repoRoot
            .appendingPathComponent(".venv-layout-analysis", isDirectory: true)
            .appendingPathComponent("bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return venvPython
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }
}

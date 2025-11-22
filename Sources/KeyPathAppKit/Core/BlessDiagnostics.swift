import Foundation
import ServiceManagement

struct BlessDiagnosticsReport {
    var helperEmbeddedPath: String
    var daemonPlistPath: String
    var helperExistsInBundle: Bool
    var daemonPlistExistsInBundle: Bool
    var smappStatus: String
    var helperDesignatedRequirement: String
    var notes: [String] = []
    // launchctl state (best-effort)
    var launchctlState: String?
    var launchctlPID: String?
    var launchctlProgram: String?
    var launchctlLastExit: String?

    func summarizedText() -> String {
        var lines: [String] = []
        let helperExistsText = helperExistsInBundle ? "yes" : "no"
        let plistExistsText = daemonPlistExistsInBundle ? "yes" : "no"
        lines.append("Helper (embedded): \(helperEmbeddedPath) exists=\(helperExistsText)")
        lines.append("Daemon Plist (embedded): \(daemonPlistPath) exists=\(plistExistsText)")
        lines.append("SMAppService status: \(smappStatus)")
        if !notes.isEmpty {
            lines.append("Notes:")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }
        if let state = launchctlState {
            lines.append("launchctl state: \(state)")
        }
        if let pid = launchctlPID {
            lines.append("launchctl pid: \(pid)")
        }
        if let prog = launchctlProgram {
            lines.append("Program: \(prog)")
        }
        if let exit = launchctlLastExit {
            lines.append("last exit status: \(exit)")
        }
        return lines.joined(separator: "\n")
    }
}

enum BlessDiagnostics {
    static func run() -> BlessDiagnosticsReport {
        let appBundlePath = Bundle.main.bundlePath
        let helperPath = appBundlePath + "/Contents/Library/HelperTools/KeyPathHelper"
        let plistPath = appBundlePath + "/Contents/Library/LaunchDaemons/com.keypath.helper.plist"

        var helperReq = ""
        var notes: [String] = []

        let helperExists = FileManager.default.fileExists(atPath: helperPath)
        if helperExists {
            let cs = runCmd("/usr/bin/codesign", ["-d", "-r-", helperPath])
            helperReq =
                (cs.out + "\n" + cs.err)
                    .components(separatedBy: "designated =>").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            notes.append("Embedded helper not found at \(helperPath)")
        }

        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        var statusText = "unknown"
        if #available(macOS 13, *) {
            let svc = SMAppService.daemon(plistName: "com.keypath.helper.plist")
            statusText = String(describing: svc.status)
        } else {
            statusText = "unsupported (macOS < 13)"
        }

        // Try to fetch launchctl state without elevation
        var launchState: String?
        var launchPID: String?
        var launchProgram: String?
        var launchLastExit: String?
        let lc = runCmd("/bin/launchctl", ["print", "system/com.keypath.helper"])
        if lc.status == 0 {
            let output = lc.out + "\n" + lc.err
            // Extract a few key fields if present
            launchState = output.components(separatedBy: "\n").first(where: { $0.contains("state =") })?
                .trimmingCharacters(in: .whitespaces)
            launchPID = output.components(separatedBy: "\n").first(where: { $0.contains("pid =") })?
                .trimmingCharacters(in: .whitespaces)
            launchProgram = output.components(separatedBy: "\n").first(where: {
                $0.contains("program =") || $0.contains("programPath =")
            })?.trimmingCharacters(in: .whitespaces)
            launchLastExit = output.components(separatedBy: "\n").first(where: {
                $0.localizedCaseInsensitiveContains("last exit status")
            })?.trimmingCharacters(in: .whitespaces)
        } else {
            notes.append("launchctl print unavailable (status=\(lc.status))")
        }

        return BlessDiagnosticsReport(
            helperEmbeddedPath: helperPath,
            daemonPlistPath: plistPath,
            helperExistsInBundle: helperExists,
            daemonPlistExistsInBundle: plistExists,
            smappStatus: statusText,
            helperDesignatedRequirement: helperReq,
            notes: notes,
            launchctlState: launchState,
            launchctlPID: launchPID,
            launchctlProgram: launchProgram,
            launchctlLastExit: launchLastExit
        )
    }

    private static func runCmd(_ launchPath: String, _ arguments: [String]) -> (
        status: Int32, out: String, err: String
    ) {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = arguments

        let outPipe = Pipe()
        p.standardOutput = outPipe
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch {
            return (127, "", "Failed to run \(launchPath): \(error)")
        }
        p.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (p.terminationStatus, out, err)
    }

    // No normalization helpers needed in the SMAppService diagnostics path.
}

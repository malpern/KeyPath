import Foundation

/// Shared launch request for starting the macOS Kanata runtime.
///
/// The current launcher still `exec`s the raw kanata binary, but callers should
/// build that command line through this model so the future in-process runtime
/// host migration can replace the handoff in one place.
public struct KanataRuntimeLaunchRequest: Sendable, Equatable {
    public let configPath: String
    public let inheritedArguments: [String]
    public let addTraceLogging: Bool

    public init(
        configPath: String,
        inheritedArguments: [String] = [],
        addTraceLogging: Bool = false
    ) {
        self.configPath = configPath
        self.inheritedArguments = inheritedArguments
        self.addTraceLogging = addTraceLogging
    }

    public func resolvedCoreBinaryPath(
        using runtimeHost: KanataRuntimeHost,
        fileManager: FileManager = .default
    ) -> String {
        runtimeHost.preferredCoreBinaryPath(fileManager: fileManager)
    }

    public func commandLine(
        using runtimeHost: KanataRuntimeHost,
        fileManager: FileManager = .default
    ) -> [String] {
        let binaryPath = resolvedCoreBinaryPath(using: runtimeHost, fileManager: fileManager)
        return commandLine(binaryPath: binaryPath)
    }

    public func commandLine(binaryPath: String) -> [String] {
        var arguments = [binaryPath, "--cfg", configPath]
        arguments.append(contentsOf: inheritedArguments)
        if addTraceLogging, !arguments.contains("--trace"), !arguments.contains("--debug") {
            arguments.append("--trace")
        }
        return arguments
    }
}

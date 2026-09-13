import ArgumentParser

public struct GlobalOptions: ParsableArguments, Sendable {
    @Flag(help: "Force JSON output")
    public var json: Bool = false

    @Flag(name: .customLong("no-json"), help: "Force human-readable output")
    public var noJson: Bool = false

    @Flag(name: .customLong("dry-run"), help: "Preview changes without applying")
    public var dryRun: Bool = false

    @Flag(name: .customLong("quiet"), help: "Suppress stderr decoration (spinners, progress, hints)")
    public var quiet: Bool = false

    @Option(name: .customLong("timeout"), help: "Timeout in seconds for IPC and network operations (default: 30)")
    public var timeout: Int = 30

    @Option(name: .customLong("on-conflict"), help: "Conflict resolution: fail|replace|skip|merge")
    public var onConflict: ConflictStrategy = .fail

    public init() {}

    public var outputContext: OutputContext {
        OutputContext.detect(forceJSON: json, forceHuman: noJson, quiet: quiet)
    }
}

public enum ConflictStrategy: String, ExpressibleByArgument, Sendable {
    case fail
    case replace
    case skip
    case merge
}

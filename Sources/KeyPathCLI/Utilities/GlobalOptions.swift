import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Flag(help: "Force JSON output")
    var json: Bool = false

    @Flag(name: .customLong("no-json"), help: "Force human-readable output")
    var noJson: Bool = false

    @Flag(name: .customLong("dry-run"), help: "Preview changes without applying")
    var dryRun: Bool = false

    @Flag(name: .customLong("quiet"), help: "Suppress stderr decoration (spinners, progress, hints)")
    var quiet: Bool = false

    @Option(name: .customLong("on-conflict"), help: "Conflict resolution: fail|replace|skip|merge")
    var onConflict: ConflictStrategy = .fail

    var outputContext: OutputContext {
        OutputContext.detect(forceJSON: json, forceHuman: noJson, quiet: quiet)
    }
}

enum ConflictStrategy: String, ExpressibleByArgument, Sendable {
    case fail
    case replace
    case skip
    case merge
}

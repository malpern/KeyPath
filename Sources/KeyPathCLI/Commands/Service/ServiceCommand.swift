import ArgumentParser

struct Service: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Check, start, stop or restart remapping; reload configuration; read logs",
        subcommands: [
            ServiceStatus.self,
            ServiceStart.self,
            ServiceStop.self,
            ServiceRestart.self,
            ServiceReload.self,
            ServiceLogs.self,
        ]
    )
}

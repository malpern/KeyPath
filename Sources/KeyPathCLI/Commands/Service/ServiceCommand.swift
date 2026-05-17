import ArgumentParser

struct Service: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Check status and control the Kanata service",
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

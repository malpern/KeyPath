import ArgumentParser

struct Rule: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rule",
        abstract: "Manage custom key remappings",
        subcommands: [
            RuleList.self,
            RuleAdd.self,
            RuleRemove.self,
            RuleShow.self,
            RuleEnable.self,
            RuleDisable.self,
            RuleEnsure.self,
        ]
    )
}

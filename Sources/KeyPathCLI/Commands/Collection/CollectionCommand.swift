import ArgumentParser

struct Collection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Manage rule collections",
        subcommands: [
            CollectionList.self,
            CollectionEnable.self,
            CollectionDisable.self,
            CollectionShow.self,
        ]
    )
}

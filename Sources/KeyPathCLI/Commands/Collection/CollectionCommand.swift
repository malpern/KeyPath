import ArgumentParser

struct Collection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Manage rule collections",
        subcommands: [
            CollectionList.self,
            CollectionCreate.self,
            CollectionEnable.self,
            CollectionDisable.self,
            CollectionShow.self,
            CollectionRename.self,
            CollectionDelete.self,
            CollectionDuplicate.self,
            CollectionReorder.self,
        ]
    )
}

import ArgumentParser

struct Layer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "layer",
        abstract: "List or switch Kanata layers",
        subcommands: [
            LayerList.self,
            LayerCreate.self,
            LayerDelete.self,
            LayerRename.self,
            LayerSwitch.self,
        ],
        defaultSubcommand: LayerList.self
    )
}

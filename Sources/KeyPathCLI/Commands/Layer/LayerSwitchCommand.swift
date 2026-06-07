import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerSwitch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch",
        abstract: "Switch to a layer by name"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Layer name (e.g., base, nav, vim)")
    var name: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = ConfigFacade()

        let layers: [String]
        do {
            layers = try await facade.tcpGetLayers()
        } catch {
            let cliError = CLIError.serviceUnreachable()
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        guard layers.contains(name) else {
            let error = CLIError.notFound("Layer", query: name, listCommand: "keypath layer list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        let success = await switchLayerAndConfirm(name, facade: facade, timeoutSeconds: globals.timeout)
        if success {
            CLIOutput.write(["layer": name], context: ctx) {
                "Switched to layer '\(name)'"
            }
        } else {
            let error = CLIError.serviceUnreachable(
                hint: "Layer switch was sent, but KeyPath could not confirm the active layer changed. Check with 'keypath layer current --json'."
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }

    private func switchLayerAndConfirm(
        _ name: String,
        facade: ConfigFacade,
        timeoutSeconds: Int
    ) async -> Bool {
        let switchTask = Task {
            await facade.tcpChangeLayer(name)
        }
        let observed = await waitForObservedLayer(name, facade: facade, timeoutSeconds: timeoutSeconds)
        switchTask.cancel()
        return observed
    }

    private func waitForObservedLayer(
        _ name: String,
        facade: ConfigFacade,
        timeoutSeconds: Int
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(max(1, timeoutSeconds)))
        repeat {
            if Task.isCancelled {
                return false
            }
            if let currentLayer = try? await facade.tcpGetCurrentLayer(),
               currentLayer == name
            {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        } while Date() < deadline

        return false
    }
}

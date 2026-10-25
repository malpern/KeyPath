import Foundation
import PackagePlugin

@main
struct CompileKeyboardStageMetal: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: any Target
    ) async throws -> [Command] {
        let shader = target.directoryURL
            .appendingPathComponent("UI/KeyboardStage/Metal/KeyboardStage.metal")
        let library = context.pluginWorkDirectoryURL
            .appendingPathComponent("default.metallib")
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

        return [
            .buildCommand(
                displayName: "Compile KeyboardStage default.metallib",
                executable: xcrun,
                arguments: [
                    "-sdk", "macosx", "metal",
                    shader.path,
                    "-o", library.path,
                ],
                inputFiles: [shader],
                outputFiles: [library]
            ),
        ]
    }
}

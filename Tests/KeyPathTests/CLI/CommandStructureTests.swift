import ArgumentParser
@testable import KeyPathCLI
import KeyPathCore
import XCTest

final class CommandStructureTests: XCTestCase {
    func testCommandNameIsKeypath() {
        XCTAssertEqual(KeyPathCLI.configuration.commandName, "keypath")
    }

    func testRootHasExpectedSubcommands() {
        let names = subcommandNames(of: KeyPathCLI.self)
        for expected in ["rule", "collection", "layer", "pack", "service", "config", "system", "export", "import", "help-topics", "completions"] {
            XCTAssertTrue(names.contains(expected), "Missing subcommand: \(expected). Found: \(names)")
        }
    }

    func testRootHasPorcelainShortcuts() {
        let names = subcommandNames(of: KeyPathCLI.self)
        XCTAssertTrue(names.contains("remap"), "Missing porcelain shortcut: remap")
        XCTAssertTrue(names.contains("logs"), "Missing porcelain shortcut: logs")
        XCTAssertTrue(names.contains("unmap"), "Missing porcelain shortcut: unmap")
    }

    func testRuleHasExpectedVerbs() {
        let names = subcommandNames(of: Rule.self)
        XCTAssertEqual(Set(names), ["list", "add", "remove", "show", "enable", "disable", "ensure"])
    }

    func testCollectionHasExpectedVerbs() {
        let names = subcommandNames(of: Collection.self)
        XCTAssertEqual(Set(names), ["list", "create", "enable", "disable", "show", "rename", "delete", "duplicate", "reorder"])
    }

    func testLayerHasExpectedVerbs() {
        let names = subcommandNames(of: Layer.self)
        XCTAssertEqual(Set(names), ["list", "current", "create", "delete", "rename", "switch"])
    }

    func testPackHasExpectedVerbs() {
        let names = subcommandNames(of: Pack.self)
        XCTAssertEqual(Set(names), ["list", "show", "install", "uninstall", "configure"])
    }

    func testServiceHasExpectedVerbs() {
        let names = subcommandNames(of: Service.self)
        XCTAssertEqual(Set(names), ["status", "start", "stop", "restart", "reload", "logs"])
    }

    func testConfigHasExpectedVerbs() {
        let names = subcommandNames(of: Config.self)
        XCTAssertEqual(Set(names), ["show", "path", "check", "apply", "backup", "restore"])
    }

    func testSystemHasExpectedVerbs() {
        let names = subcommandNames(of: System.self)
        XCTAssertEqual(Set(names), ["inspect"])
    }

    /// Runtime control goes through the running app (RuntimeControl); install,
    /// repair and uninstall stay in KeyPath.app.
    func testRuntimeCommandsParseAndSystemLifecycleStaysUnavailable() throws {
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "status", "--json"]) is ServiceStatus)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "start"]) is ServiceStart)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "stop"]) is ServiceStop)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "restart", "--timeout", "60"]) is ServiceRestart)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["status"]) is StatusShortcut)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["start"]) is StartShortcut)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["stop"]) is StopShortcut)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["restart"]) is RestartShortcut)

        let commands = [["system", "install"], ["system", "repair"], ["system", "uninstall"]]
        for arguments in commands {
            for flags in [[], ["--json"], ["--dry-run"]] {
                XCTAssertThrowsError(try KeyPathCLI.parseAsRoot(arguments + flags), arguments.joined(separator: " ")) { error in
                    XCTAssertNotEqual(KeyPathCLI.exitCode(for: error), .success)
                }
            }
        }
    }

    func testLifecycleCommandsParse() throws {
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["doctor", "--json"]) is Doctor)
        let setup = try XCTUnwrap(KeyPathCLI.parseAsRoot(["setup", "--wait", "60", "--no-open"]) as? Setup)
        XCTAssertEqual(setup.wait, 60)
        XCTAssertTrue(setup.noOpen)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["repair"]) is Setup, "repair is an alias for setup")
        let uninstall = try XCTUnwrap(KeyPathCLI.parseAsRoot(["uninstall", "--yes", "--reset-permissions"]) as? Uninstall)
        XCTAssertTrue(uninstall.yes)
        XCTAssertTrue(uninstall.resetPermissions)
    }

    /// Without --yes nothing is sent to the app: the plan prints and the exit is 2.
    func testUninstallWithoutYesChangesNothing() async throws {
        for arguments in [["uninstall"], ["uninstall", "--json"], ["uninstall", "--yes", "--dry-run"]] {
            var command = try XCTUnwrap(KeyPathCLI.parseAsRoot(arguments) as? Uninstall)
            do {
                try await command.run()
                XCTFail("\(arguments) must refuse")
            } catch let exit as ExitCode {
                XCTAssertEqual(exit.rawValue, 2, arguments.joined(separator: " "))
            }
        }
    }

    func testSupportedConfigSimulatorAndDiagnosticsRemainRegistered() throws {
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["config", "check", "--json"]) is ConfigCheck)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["simulate", "a", "--dry-run"]) is Simulate)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "reload"]) is ServiceReload)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "logs"]) is ServiceLogs)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["system", "inspect"]) is SystemInspect)
        XCTAssertTrue(KeyPathCLI.helpMessage().contains("keypath status|start|stop|restart"))
    }

    func testCompletionsOmitUnavailableCommandsAndKeepReload() {
        let completions = KeyPathCLI.completionScript(for: .zsh)
        for command in ["system_install", "system_repair", "system_uninstall"] {
            XCTAssertFalse(completions.contains("_keypath_\(command)"))
        }
        for command in ["service_status", "service_start", "service_stop", "service_restart"] {
            XCTAssertTrue(completions.contains("_keypath_\(command)"))
        }
        XCTAssertTrue(completions.contains("_keypath_service_reload"))
        XCTAssertTrue(completions.contains("_keypath_config_check"))
    }

    func testHelpTopicsHasExpectedVerbs() {
        let names = subcommandNames(of: Help.self)
        XCTAssertEqual(Set(names), ["schemas", "examples"])
    }

    func testCompletionsHasShells() {
        let names = subcommandNames(of: Completions.self)
        XCTAssertEqual(Set(names), ["zsh", "bash", "fish", "install", "install-man", "values"])
    }

    // MARK: - Helpers

    private func subcommandNames<T: ParsableCommand>(of _: T.Type) -> [String] {
        T.configuration.subcommands.map {
            $0.configuration.commandName ?? String(describing: $0).lowercased()
        }
    }

    /// Phase 4e: `keypath doctor` prints the admission engine's verdicts.
    func testDoctorRendersAdmissionFindings() {
        var response = RuntimeControl.Response(ok: true, operation: .doctor, state: .stopped, workerPID: nil, failure: nil,
                                               lastError: nil, layer: nil, appPID: 1, appVersion: "1")
        XCTAssertEqual(RuntimeControlClient.humanAdmission(response, noColor: true), "")
        response.admission = [
            .init(severity: "blocking", subject: "Louder", title: "Louder can't run here",
                  explanation: "Louder sends volu, which the current backend can't send.", fixes: ["Turn off Louder"]),
            .init(severity: "needsChoice", subject: "A", title: "Key conflict on f13",
                  explanation: "A and B both map f13 on the base layer. Only one can win.", fixes: ["Turn off A", "Turn off B"]),
            .init(severity: "automatic", subject: "Mine", title: "Caps Lock will use F19",
                  explanation: "Mine uses F18, which KeyPath had reserved for Caps Lock. Caps Lock will use F19 instead.", fixes: [])
        ]
        XCTAssertEqual(RuntimeControlClient.humanAdmission(response, noColor: true), """
        Rules:
        ✗ Louder can't run here
            Louder sends volu, which the current backend can't send.
            Fix: Turn off Louder
        ! Key conflict on f13
            A and B both map f13 on the base layer. Only one can win.
            Fix: Turn off A / Turn off B
        • Caps Lock will use F19
            Mine uses F18, which KeyPath had reserved for Caps Lock. Caps Lock will use F19 instead.
        """)
    }
}

import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathCLI {
    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install KeyPath services and components"
        )

        @Flag(help: "Output as JSON")
        var json: Bool = false

        mutating func run() async throws {
            let facade = CLIFacade()
            print("Starting installation...")
            let report = await facade.runInstall()

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                printInstallerReport(report, title: "Installation")
            }

            if !report.success {
                throw ExitCode.failure
            }
        }
    }

    struct Repair: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Repair broken or unhealthy services"
        )

        @Flag(help: "Output as JSON")
        var json: Bool = false

        mutating func run() async throws {
            let facade = CLIFacade()
            print("Starting repair...")
            let report = await facade.runRepair()

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                if report.fastRepair {
                    print("Repair completed via KanataService restart.")
                } else {
                    printInstallerReport(report, title: "Repair")
                }
            }

            if !report.success {
                throw ExitCode.failure
            }
        }
    }

    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove KeyPath services and components"
        )

        @Flag(help: "Also delete user configuration files")
        var deleteConfig: Bool = false

        @Flag(help: "Output as JSON")
        var json: Bool = false

        mutating func run() async throws {
            let facade = CLIFacade()
            if deleteConfig {
                print("Starting uninstall (configuration will be deleted)...")
            } else {
                print("Starting uninstall (configuration will be preserved)...")
            }
            let report = await facade.runUninstall(deleteConfig: deleteConfig)

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                printInstallerReport(report, title: "Uninstall")
            }

            if !report.success {
                throw ExitCode.failure
            }
        }
    }

    struct Inspect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect system state without making changes"
        )

        @Flag(help: "Output as JSON")
        var json: Bool = false

        mutating func run() async throws {
            let facade = CLIFacade()
            let result = await facade.runInspect()

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print("=== System Inspection ===")
                print("macOS Version: \(result.macOSVersion)")
                print("Driver Compatible: \(result.driverCompatible ? "Yes" : "No")")
                print("\nPlan Status: \(result.planStatus)")
                if let blockedBy = result.blockedBy {
                    print("Blocked By: \(blockedBy)")
                }
                if !result.plannedRecipes.isEmpty {
                    print("\nPlanned Recipes:")
                    for recipe in result.plannedRecipes {
                        print("  - \(recipe)")
                    }
                }
                print("\nNo changes were made to the system.")
            }
        }
    }
}

func printInstallerReport(_ report: CLIInstallerReport, title: String) {
    print("\n=== \(title) Report ===")
    print("Success: \(report.success ? "Yes" : "No")")

    if let reason = report.failureReason {
        print("Failure Reason: \(reason)")
    }

    if !report.steps.isEmpty {
        print("\nSteps:")
        for step in report.steps {
            let status = step.success ? "OK" : "FAIL"
            print("  [\(status)] \(step.name)")
            if let error = step.error {
                print("         \(error)")
            }
        }
    }
}

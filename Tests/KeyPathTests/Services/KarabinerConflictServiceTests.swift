import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import Testing

@MainActor
@Suite("KarabinerConflictService Tests", .serialized)
struct KarabinerConflictServiceTests {
    @Test("Karabiner grabber detection uses injected SystemStateProvider")
    func karabinerGrabberDetectionUsesInjectedSystemStateProvider() async {
        KarabinerConflictService.testDaemonRunning = nil
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "karabiner_grabber" ? [1111] : []
        }

        let provider = SystemStateProvider(subprocessRunner: runner)
        let service = KarabinerConflictService(systemStateProvider: provider)

        let isRunning = await service.isKarabinerElementsRunning()
        let commands = await runner.executedCommands

        #expect(isRunning)
        #expect(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "karabiner_grabber"] },
            "KarabinerConflictService should use the injected provider for grabber discovery"
        )
    }

    @Test("VirtualHID daemon detection uses injected SystemStateProvider")
    func virtualHIDDaemonDetectionUsesInjectedSystemStateProvider() async {
        KarabinerConflictService.testDaemonRunning = nil
        FeatureFlags.testStartupMode = false
        defer { FeatureFlags.testStartupMode = nil }
        ServiceBootstrapper.setRestartTimeForTesting(
            Date().addingTimeInterval(-60),
            serviceID: "com.keypath.karabiner-vhiddaemon"
        )
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "VirtualHIDDevice-Daemon" ? [2222] : []
        }

        let provider = SystemStateProvider(subprocessRunner: runner)
        let service = KarabinerConflictService(systemStateProvider: provider)

        let isRunning = await service.isKarabinerDaemonRunning()
        let commands = await runner.executedCommands

        #expect(isRunning)
        #expect(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "VirtualHIDDevice-Daemon"] },
            "KarabinerConflictService should use the injected provider for daemon discovery"
        )
    }

    @Test("Stopped-process verification uses injected SystemStateProvider")
    func stoppedProcessVerificationUsesInjectedSystemStateProvider() async {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "Karabiner-DriverKit-VirtualHIDDevice" ? [3333] : []
        }

        let provider = SystemStateProvider(subprocessRunner: runner)
        let service = KarabinerConflictService(systemStateProvider: provider)

        let isStopped = await service.checkProcessStopped(
            pattern: "Karabiner-DriverKit-VirtualHIDDevice",
            processName: "VirtualHIDDevice Driver"
        )
        let commands = await runner.executedCommands

        #expect(!isStopped)
        #expect(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "Karabiner-DriverKit-VirtualHIDDevice"] },
            "KarabinerConflictService should use the injected provider for stopped-process verification"
        )
    }
}

import Foundation
import XCTest
@testable import KeyPath

@MainActor
final class HealthCheckServiceTests: XCTestCase {
    // Minimal test double for DiagnosticsManaging focusing on checkHealth
    final class FakeDiagnosticsManager: DiagnosticsManaging {
        var nextStatus: ServiceHealthStatus = .healthy()

        func addDiagnostic(_ diagnostic: KanataDiagnostic) {}
        func getDiagnostics() -> [KanataDiagnostic] { [] }
        func clearDiagnostics() {}
        func startLogMonitoring() {}
        func stopLogMonitoring() {}
        func checkHealth(processStatus _: ProcessHealthStatus, tcpPort _: Int) async -> ServiceHealthStatus { nextStatus }
        func canRestartService() async -> RestartCooldownState { .init(canRestart: true, remainingCooldown: 0, attemptsSinceLastSuccess: 0, isInGracePeriod: false) }
        func recordStartAttempt(timestamp _: Date) async {}
        func recordStartSuccess() async {}
        func recordConnectionSuccess() async {}
        func diagnoseFailure(exitCode _: Int32, output _: String) -> [KanataDiagnostic] { [] }
        func getSystemDiagnostics(engineClient _: EngineClient?) async -> [KanataDiagnostic] { [] }
    }

    func testEvaluate_Healthy_NoRestart() async {
        let fake = FakeDiagnosticsManager()
        fake.nextStatus = .healthy()
        let service = HealthCheckService(
            diagnosticsManager: fake,
            statusProvider: { (true, 123) }
        )

        let decision = await service.evaluate(tcpPort: 37001)
        XCTAssertTrue(decision.isHealthy)
        XCTAssertFalse(decision.shouldRestart)
        XCTAssertNil(decision.reason)
    }

    func testEvaluate_Unhealthy_ShouldRestart() async {
        let fake = FakeDiagnosticsManager()
        fake.nextStatus = .unhealthy(reason: "tcp down", shouldRestart: true)
        let service = HealthCheckService(
            diagnosticsManager: fake,
            statusProvider: { (true, 123) }
        )

        let decision = await service.evaluate(tcpPort: 37001)
        XCTAssertFalse(decision.isHealthy)
        XCTAssertTrue(decision.shouldRestart)
        XCTAssertEqual(decision.reason, "tcp down")
    }
}



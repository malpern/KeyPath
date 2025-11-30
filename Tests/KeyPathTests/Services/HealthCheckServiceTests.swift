import Foundation
@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class HealthCheckServiceTests: XCTestCase {
    // Minimal test double for DiagnosticsManaging focusing on checkHealth
    final class FakeDiagnosticsManager: DiagnosticsManaging, @unchecked Sendable {
        var nextStatus: ServiceHealthStatus = .healthy()

        func addDiagnostic(_: KanataDiagnostic) {}
        func getDiagnostics() -> [KanataDiagnostic] { [] }
        func clearDiagnostics() {}
        func startLogMonitoring() {}
        func stopLogMonitoring() {}
        func checkHealth(tcpPort _: Int) async -> ServiceHealthStatus { nextStatus }
        func diagnoseFailure(exitCode _: Int32, output _: String) -> [KanataDiagnostic] { [] }
        func getSystemDiagnostics(engineClient _: EngineClient?) async -> [KanataDiagnostic] { [] }
    }

    func testEvaluate_Healthy_NoRestart() async {
        let fake = FakeDiagnosticsManager()
        fake.nextStatus = .healthy()
        let service = HealthCheckService(diagnosticsManager: fake)

        let decision = await service.evaluate(tcpPort: 37001)
        XCTAssertTrue(decision.isHealthy)
        XCTAssertFalse(decision.shouldRestart)
        XCTAssertNil(decision.reason)
    }

    func testEvaluate_Unhealthy_ShouldRestart() async {
        let fake = FakeDiagnosticsManager()
        fake.nextStatus = .unhealthy(reason: "tcp down", shouldRestart: true)
        let service = HealthCheckService(diagnosticsManager: fake)

        let decision = await service.evaluate(tcpPort: 37001)
        XCTAssertFalse(decision.isHealthy)
        XCTAssertTrue(decision.shouldRestart)
        XCTAssertEqual(decision.reason, "tcp down")
    }
}

#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Traces the Fix button flow using the InstallerEngine façade:
/// detect → map auto-fix action → execute plan.
@main
struct TestFixButtonFlow {
    static func main() async {
        print("🔍 Testing Fix Button Flow via InstallerEngine")
        print(String(repeating: "=", count: 56))

        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        // 1) Detect
        let context = await engine.inspectSystem()
        let services = context.services.launchDaemons
        let missingKanata = !(services.kanataServiceLoaded && services.kanataServiceHealthy)

        print("\n📋 Detection:")
        print("  kanataService loaded:  \(services.kanataServiceLoaded)")
        print("  kanataService healthy: \(services.kanataServiceHealthy)")

        // 2) Decide action (mirrors WizardAutoFixer mapping)
        let intent: InstallIntent = missingKanata ? .install : .repair
        print("  → Chosen intent: \(intent)")

        // 3) Plan
        let plan = await engine.makePlan(for: intent, context: context)
        print("\n🗺️  Plan status: \(plan.status)")
        plan.recipes.enumerated().forEach { idx, recipe in
            print("   \(idx + 1). [\(recipe.type)] \(recipe.id)")
        }

        guard case .ready = plan.status else {
            print("⚠️ Plan blocked; aborting execution")
            return
        }

        // 4) Execute
        print("\n⚙️  Executing plan…")
        let report = await engine.execute(plan: plan, using: broker)
        print("✅ Result: \(report.success ? "SUCCESS" : "FAILED")")
        if let reason = report.failureReason {
            print("   Reason: \(reason)")
        }
    }
}

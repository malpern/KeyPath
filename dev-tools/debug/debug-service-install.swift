#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Preview the InstallerEngine install flow instead of re-creating plists by hand.
/// Inspects, builds an install plan, and (optionally) executes it using the façade.
@main
struct DebugServiceInstall {
    static func main() async {
        print("🔧 InstallerEngine install plan preview")
        print(String(repeating: "=", count: 44))

        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)

        print("\n📋 Plan status: \(plan.status)")
        for (idx, recipe) in plan.recipes.enumerated() {
            print("  \(idx + 1). [\(recipe.type)] \(recipe.id)")
        }

        guard case .ready = plan.status else {
            print("⚠️ Plan blocked; not executing")
            return
        }

        print("\n⚙️  Executing install plan…")
        let report = await engine.execute(plan: plan, using: broker)
        let result = report.success ? "SUCCESS" : "FAILED"
        print("✅ Result: \(result)")
        if let reason = report.failureReason {
            print("   Reason: \(reason)")
        }
    }
}

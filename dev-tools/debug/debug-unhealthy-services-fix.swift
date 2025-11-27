#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Debug helper that reuses the InstallerEngine façade to inspect and repair unhealthy services.
/// Run from repo root (after building) with:
///   swift dev-tools/debug/debug-unhealthy-services-fix.swift
/// The script uses the same code paths as the wizard: inspect -> plan (repair) -> execute.
@main
struct DebugUnhealthyServicesFix {
    static func main() async {
        print("🔍 InstallerEngine: inspect → repair (unhealthy services)")
        print(String(repeating: "=", count: 64))

        let engine = InstallerEngine()
        let broker = PrivilegeBroker()

        // 1) Inspect current system state
        let context = await engine.inspectSystem()
        dumpServiceHealth(context.services)

        // 2) Build a repair plan (no changes yet)
        let plan = await engine.makePlan(for: .repair, context: context)
        dumpPlan(plan)

        guard case .ready = plan.status else {
            print("⚠️ Plan blocked: \(String(describing: plan.blockedBy?.name))")
            return
        }

        // 3) Execute the plan using the façade broker
        print("\n⚙️  Executing repair plan…")
        let report = await engine.execute(plan: plan, using: broker)
        dumpReport(report)
    }

    private static func dumpServiceHealth(_ status: HealthStatus) {
        print("\n📊 Service health snapshot:")
        print("  Kanata running:        \(status.kanata.isRunning)")
        print("  Kanata responding:     \(status.kanata.isResponding)")
        print("  VHID daemon loaded:    \(status.launchDaemons.vhidDaemonServiceLoaded)")
        print("  VHID manager loaded:   \(status.launchDaemons.vhidManagerServiceLoaded)")
        print("  VHID daemon healthy:   \(status.launchDaemons.vhidDaemonServiceHealthy)")
        print("  VHID manager healthy:  \(status.launchDaemons.vhidManagerServiceHealthy)")
    }

    private static func dumpPlan(_ plan: InstallPlan) {
        print("\n📋 Repair plan for intent \(plan.intent):")
        print("  Status: \(plan.status)")
        if !plan.recipes.isEmpty {
            print("  Recipes:")
            for (idx, recipe) in plan.recipes.enumerated() {
                print("   \(idx + 1). [\(recipe.type)] \(recipe.id)")
            }
        } else {
            print("  (no recipes generated)")
        }
    }

    private static func dumpReport(_ report: InstallerReport) {
        print("\n✅ Execution result: \(report.success ? "SUCCESS" : "FAILED")")
        if let reason = report.failureReason {
            print("  Reason: \(reason)")
        }
        if !report.unmetRequirements.isEmpty {
            print("  Unmet requirements:")
            report.unmetRequirements.forEach { print("   - \($0.name)") }
        }
        if !report.executedRecipes.isEmpty {
            print("  Executed recipes:")
            report.executedRecipes.forEach { print("   - \($0.recipeID): \($0.success ? "ok" : "failed")") }
        }
    }
}

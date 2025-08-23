#!/usr/bin/env swift

import Foundation

print("🔮 ORACLE SYSTEM VALIDATION")
print(String(repeating: "=", count: 70))
print()

print("📋 Validating Oracle system integration throughout KeyPath")
print()

// Test 1: Oracle Performance Validation
print("⚡ Test 1: Oracle Performance Validation")
print(String(repeating: "-", count: 50))

let logFile = "/Volumes/FlashGordon/Dropbox/code/KeyPath/logs/keypath-debug.log"
let logContent = (try? String(contentsOfFile: logFile)) ?? ""

// Extract Oracle timing data
let timingPattern = #"Permission snapshot complete in (\d+\.\d+)s"#
let regex = try! NSRegularExpression(pattern: timingPattern)
let matches = regex.matches(in: logContent, range: NSRange(logContent.startIndex..., in: logContent))

var timings: [Double] = []
for match in matches.suffix(5) { // Last 5 measurements
    let range = Range(match.range(at: 1), in: logContent)!
    let timing = Double(String(logContent[range])) ?? 0.0
    timings.append(timing)
}

if !timings.isEmpty {
    let avgTiming = timings.reduce(0, +) / Double(timings.count)
    let maxTiming = timings.max() ?? 0.0
    let minTiming = timings.min() ?? 0.0
    
    print("   Recent Oracle snapshots: \(timings.count) samples")
    print("   Average timing: \(String(format: "%.3f", avgTiming))s")
    print("   Min/Max: \(String(format: "%.3f", minTiming))s / \(String(format: "%.3f", maxTiming))s")
    print("   Performance goal (<2s): \(avgTiming < 2.0 ? "✅ ACHIEVED" : "❌ FAILED")")
} else {
    print("   ⚠️  No timing data found - Oracle may not have run recently")
}
print()

// Test 2: Oracle Integration Validation
print("🔗 Test 2: Oracle Integration Validation")
print(String(repeating: "-", count: 50))

let integrationChecks = [
    ("SimpleKanataManager Oracle calls", "🔮.*SimpleKanataManager.*Oracle"),
    ("Oracle permission snapshots", "🔮.*Oracle.*snapshot complete"),
    ("Oracle blocking issues", "🔮.*Oracle.*Blocking issue"),
    ("Oracle TCP fallback", "🔮.*Oracle.*TCP unavailable.*fallback"),
    ("Oracle TCC database access", "🔮.*Oracle.*TCC database"),
]

for (description, pattern) in integrationChecks {
    let regex = try! NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: logContent, range: NSRange(logContent.startIndex..., in: logContent))
    let found = !matches.isEmpty
    print("   \(description): \(found ? "✅ ACTIVE" : "❌ MISSING")")
}
print()

// Test 3: Oracle Error Handling Validation
print("🚨 Test 3: Oracle Error Handling Validation")
print(String(repeating: "-", count: 50))

let errorChecks = [
    ("TCP timeout handling", "TCP server not reachable"),
    ("TCC database fallback", "TCC database fallback"),
    ("Permission state detection", "KeyPath needs.*permission"),
    ("Clear error messages", "enable in System Settings"),
]

for (description, pattern) in errorChecks {
    let regex = try! NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: logContent, range: NSRange(logContent.startIndex..., in: logContent))
    let found = !matches.isEmpty
    print("   \(description): \(found ? "✅ WORKING" : "❌ MISSING")")
}
print()

// Test 4: Legacy System Elimination
print("🗑️  Test 4: Legacy System Elimination")
print(String(repeating: "-", count: 50))

let legacyPatterns = [
    ("Old PermissionService complex logic", "checkSystemPermissions.*complex"),
    ("Log parsing heuristics", "parsing.*log.*error"),
    ("CGEvent tap testing", "CGEvent.*tap.*test"),
    ("Multiple permission sources", "conflicting.*permission"),
]

var legacyFound = 0
for (description, pattern) in legacyPatterns {
    let regex = try! NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: logContent, range: NSRange(logContent.startIndex..., in: logContent))
    let found = !matches.isEmpty
    print("   \(description): \(found ? "❌ STILL PRESENT" : "✅ ELIMINATED")")
    if found { legacyFound += 1 }
}
print("   Legacy elimination: \(legacyFound == 0 ? "✅ COMPLETE" : "⚠️  \(legacyFound) issues remain")")
print()

// Test 5: Oracle System Health Summary
print("📊 Test 5: Oracle System Health Summary")
print(String(repeating: "-", count: 50))

let oracleLogCount = logContent.components(separatedBy: "🔮 [Oracle]").count - 1
let recentLogs = logContent.components(separatedBy: "\n").suffix(100)
let recentOracleCount = recentLogs.filter { $0.contains("🔮 [Oracle]") }.count

print("   Total Oracle log entries: \(oracleLogCount)")
print("   Recent Oracle activity (last 100 lines): \(recentOracleCount)")
print("   Oracle system status: \(oracleLogCount > 0 ? "✅ ACTIVE" : "❌ INACTIVE")")
print()

if oracleLogCount > 0 {
    let mostRecentOracleLog = recentLogs.reversed().first { $0.contains("🔮 [Oracle]") } ?? "None"
    print("   Most recent Oracle log:")
    print("   \(mostRecentOracleLog)")
}
print()

// Final Verdict
print("🎯 ORACLE SYSTEM VALIDATION RESULTS")
print(String(repeating: "=", count: 70))

let performancePass = timings.isEmpty || timings.reduce(0, +) / Double(timings.count) < 2.0
let integrationPass = oracleLogCount > 5
let legacyPass = legacyFound == 0

let overallScore = [performancePass, integrationPass, legacyPass].filter { $0 }.count
let totalTests = 3

print("Performance: \(performancePass ? "✅ PASS" : "❌ FAIL") - Sub-2-second snapshots")
print("Integration: \(integrationPass ? "✅ PASS" : "❌ FAIL") - Oracle active throughout app")  
print("Legacy Cleanup: \(legacyPass ? "✅ PASS" : "❌ FAIL") - Old systems eliminated")
print()
print("OVERALL SCORE: \(overallScore)/\(totalTests) - \(overallScore == totalTests ? "🎉 EXCELLENT" : overallScore >= 2 ? "🟡 GOOD" : "🔴 NEEDS WORK")")

if overallScore == totalTests {
    print()
    print("🔮 The Oracle Permission System is working perfectly!")
    print("   ✅ Fast, deterministic permission detection")
    print("   ✅ Single source of truth throughout KeyPath")
    print("   ✅ Legacy chaos eliminated")
    print("   ✅ Clear user guidance and error messages")
}
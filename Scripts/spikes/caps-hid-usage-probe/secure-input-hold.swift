// Spike helper: hold Secure Event Input for N seconds, then release it.
import Carbon
import Foundation
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "10") ?? 10
print("enable:", EnableSecureEventInput(), "now:", IsSecureEventInputEnabled()); fflush(stdout)
Thread.sleep(forTimeInterval: seconds)
print("disable:", DisableSecureEventInput(), "now:", IsSecureEventInputEnabled())

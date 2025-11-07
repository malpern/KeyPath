import Foundation
import ServiceManagement

@main
struct SMAppServicePOC {
  static func main() {
    let args = CommandLine.arguments.dropFirst()
    guard let plistName = args.first else {
      print("Usage: smappservice-poc <plistName> [action]\n  action: status|register|unregister (default: status)")
      exit(2)
    }
    let action = args.dropFirst().first ?? "status"

    let svc = SMAppService.daemon(plistName: plistName)

    func printStatus(_ prefix: String) {
      let status = svc.status
      print("\(prefix) status=\(status.rawValue) (0=notRegistered,1=enabled,2=requiresApproval,3=notFound)")
    }

    switch action {
    case "status":
      printStatus("SMAppService")

    case "register":
      printStatus("Before register")
      do {
        try svc.register()
        print("✅ register() succeeded")
      } catch {
        print("❌ register() failed: \(error)")
      }
      printStatus("After register")

    case "unregister":
      printStatus("Before unregister")
      if #available(macOS 13, *) {
        do {
          try awaitUnregister(svc)
          print("✅ unregister() succeeded")
        } catch {
          print("❌ unregister() failed: \(error)")
        }
      } else {
        print("⚠️ unregister requires macOS 13+")
      }
      printStatus("After unregister")

    default:
      print("Unknown action: \(action)")
      exit(2)
    }
  }

  @available(macOS 13, *)
  private static func awaitUnregister(_ svc: SMAppService) throws {
    var thrown: Error?
    let sema = DispatchSemaphore(value: 0)
    Task {
      do { try await svc.unregister() } catch { thrown = error }
      sema.signal()
    }
    _ = sema.wait(timeout: .now() + 10)
    if let thrown { throw thrown }
  }
}



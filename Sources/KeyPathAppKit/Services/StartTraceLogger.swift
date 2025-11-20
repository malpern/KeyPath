import Foundation
import KeyPathCore

enum StartTraceLogger {
  static func logStartCallStack(maxFrames: Int = 5) {
    AppLogger.shared.log("📞 [Trace] startKanata() called from:")
    for (index, symbol) in Thread.callStackSymbols.prefix(maxFrames).enumerated() {
      AppLogger.shared.log("📞 [Trace] [\(index)] \(symbol)")
    }
  }
}

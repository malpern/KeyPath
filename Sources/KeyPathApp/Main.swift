import KeyPathAppKit
import SwiftUI

@main
struct KeyPath {
    static func main() async {
        if await SessionRuntimeWorker.runIfRequested() { return }
        KeyPathApp.main()
    }
}

import KeyPath  // Import the library with our SwiftUI app
import SwiftUI

// Re-add @main attribute to launch the SwiftUI app
// This is in a separate target so SPM can build it as an executable
@main
struct KeyPathLauncher {
  static func main() {
    // Create and run the SwiftUI app
    KeyPathApp.main()
  }
}

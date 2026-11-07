import SwiftUI

/// Empty host app. XCUITest bundles need a target application to build against;
/// at runtime the runner attaches to your real app by bundle identifier instead.
@main
struct ProofRunnerHostApp: App {
    var body: some Scene {
        WindowGroup { Text("proof runner host") }
    }
}

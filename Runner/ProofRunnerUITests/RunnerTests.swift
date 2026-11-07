import XCTest

/// One long-running UI test that serves commands from the proof CLI over localhost.
/// The simulator shares the Mac's loopback, so the CLI talks to 127.0.0.1:<port>.
/// It attaches to any installed app via XCUIApplication(bundleIdentifier:), so the
/// app under test needs no UI test target.
final class RunnerTests: XCTestCase {
    /// Issues XCTest records during a command (e.g. "not hittable") are returned to the CLI as errors
    /// instead of being lost in the xcodebuild log.
    static var lastIssue: String?

    override func record(_ issue: XCTIssue) {
        RunnerTests.lastIssue = issue.compactDescription
        // Do not call super: a recorded failure must not end the serving loop.
    }

    func testServe() throws {
        continueAfterFailure = true
        executionTimeAllowance = 60 * 60 * 24
        let env = ProcessInfo.processInfo.environment
        let port = UInt16(env["PROOF_PORT"] ?? "") ?? 22087
        let handler = CommandHandler()
        let server = try RunnerServer(port: port, handler: handler)
        server.start()
        NSLog("proof-runner: listening on 127.0.0.1:\(port)")
        while !server.shouldStop {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
        }
        server.stop()
    }
}

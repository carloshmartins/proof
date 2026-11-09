import XCTest
@testable import ProofKit

final class ProgressTests: XCTestCase {
    func activity(_ lines: [String]) -> BuildActivity {
        var a = BuildActivity()
        lines.forEach { a.consume($0) }
        return a
    }

    func testCompileStepsNameTheFileAndCount() {
        let a = activity([
            "Resolve Package Graph",
            "CompileSwift normal arm64 /Users/me/dev/App/Modules/Login/Sources/LoginView.swift (in target 'Login' from project 'App')",
            "SwiftCompile normal arm64 Compiling\\ My\\ View.swift /Users/me/dev/App/My\\ View.swift (in target 'App' from project 'App')",
            "CompileC /tmp/x.o /Users/me/dev/App/Legacy/Bridge.m normal arm64 objective-c",
        ])
        XCTAssertEqual(a.compiled, 3)
        XCTAssertEqual(a.step, "compiling Bridge.m")
        XCTAssertEqual(a.summary, "compiling Bridge.m · 3 files")
        XCTAssertEqual(activity(["SwiftCompile normal arm64 /a/My\\ View.swift"]).step, "compiling My View.swift")
    }

    func testBuildPhases() {
        XCTAssertEqual(activity(["Resolve Package Graph"]).step, "resolving packages")
        XCTAssertEqual(activity(["Ld /Users/me/DD/Build/Products/Debug-iphonesimulator/App.app/App normal (in target 'App')"]).step, "linking App")
        XCTAssertEqual(activity(["PhaseScriptExecution SwiftLint\\ Run /tmp/Script-1.sh (in target 'App')"]).step, "running script SwiftLint Run")
        XCTAssertEqual(activity(["CodeSign /Users/me/DD/App.app (in target 'App')"]).step, "signing")
        XCTAssertEqual(activity(["   ", "random noise"]).step, "starting")
    }

    func testTestsAreCountedForXCTestAndSwiftTesting() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test-failed", withExtension: "log", subdirectory: "Fixtures"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        let a = activity(lines)
        XCTAssertEqual(a.testsFailed, 3, "same failures the brief parser finds")
        XCTAssertEqual(a.testsPassed, 3)

        let running = activity(["Test Case '-[LoginTests.LoginViewModelTests testValidEmail]' started."])
        XCTAssertEqual(running.step, "testing LoginViewModelTests.testValidEmail")
        XCTAssertEqual(activity(["◇ Test progressSmoothing() started."]).step, "testing progressSmoothing()")
        XCTAssertEqual(activity(["Test Case '-[A.B t]' started.", "Test Case '-[A.B t]' passed (0.1 seconds)."]).summary,
                       "testing B.t · 1 passed")
    }

    func testFeedSplitsChunksIntoLines() {
        let p = ProgressLine("building", interactive: false, heartbeat: 3600)
        defer { p.finish() }
        p.feed(Data("CompileSwift normal arm64 /a/Fo".utf8))
        p.feed(Data("o.swift\nCompileSwift normal arm64 /a/Bar.swift\n".utf8))
        XCTAssertEqual(p.current.compiled, 2)
        XCTAssertEqual(p.current.step, "compiling Bar.swift")
        p.finish()
        p.feed(Data("CompileSwift normal arm64 /a/Late.swift\n".utf8))
        XCTAssertEqual(p.current.compiled, 2, "ignored after finish")
    }

    func testElapsedAndTruncate() {
        XCTAssertEqual(ProgressLine.elapsed(9.7), "9s")
        XCTAssertEqual(ProgressLine.elapsed(65), "1m05s")
        XCTAssertEqual(ProgressLine.truncate("abcdef", to: 4), "abc…")
        XCTAssertEqual(ProgressLine.truncate("abc", to: 4), "abc")
    }
}

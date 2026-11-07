import XCTest
@testable import ProofKit

final class FlowStepTests: XCTestCase {
    func testTokenizeQuotesEscapesAndComments() throws {
        XCTAssertEqual(try FlowStep.tokenize(#"type "me@x.com" --id login.email --clear  # the email"#),
                       ["type", "me@x.com", "--id", "login.email", "--clear"])
        XCTAssertEqual(try FlowStep.tokenize(#"tap --label "Say \"hi\"""#), ["tap", "--label", #"Say "hi""#])
        XCTAssertEqual(try FlowStep.tokenize("tap --label 'Log in'"), ["tap", "--label", "Log in"])
        XCTAssertEqual(try FlowStep.tokenize(##"tap --label "#1 pick""##), ["tap", "--label", "#1 pick"], "# inside quotes is text")
        XCTAssertEqual(try FlowStep.tokenize("   # only a comment"), [])
        XCTAssertThrowsError(try FlowStep.tokenize(#"tap --label "open"#))
    }

    func testParseAndRoundTrip() throws {
        let line = #"type "Hello world" --id note.body --clear --submit"#
        let step = try XCTUnwrap(try FlowStep.parse(line: line))
        XCTAssertEqual(step.action, "type")
        XCTAssertEqual(step.positional, ["Hello world"])
        XCTAssertEqual(step.option("id"), "note.body")
        XCTAssertEqual(step.flags, ["clear", "submit"])
        XCTAssertEqual(step.line, line)
        XCTAssertEqual(try FlowStep.parse(line: step.line), step)
    }

    func testUnknownStepNamesLine() {
        XCTAssertThrowsError(try FlowStep.parse(line: "clickk --id x", line: 4)) { e in
            XCTAssertTrue("\(e)".contains("line 4: unknown step 'clickk'"))
        }
    }

    func testRunnerRequests() throws {
        func req(_ l: String) throws -> (String, [String: Any]) {
            try XCTUnwrap(try XCTUnwrap(try FlowStep.parse(line: l)).runnerRequest(defaultBundleId: "com.app"))
        }
        let (p1, b1) = try req("tap --type button --label Save --index 1")
        XCTAssertEqual(p1, "/tap")
        XCTAssertEqual(b1["type"] as? String, "button")
        XCTAssertEqual(b1["index"] as? Int, 1)
        let (p2, b2) = try req("launch --arg -reset --arg -mock --env API=staging")
        XCTAssertEqual(p2, "/launch")
        XCTAssertEqual(b2["bundleId"] as? String, "com.app")
        XCTAssertEqual(b2["arguments"] as? [String], ["-reset", "-mock"])
        XCTAssertEqual(b2["environment"] as? [String: String], ["API": "staging"])
        let (p3, b3) = try req("expect --id home.title")
        XCTAssertEqual(p3, "/wait")
        XCTAssertEqual(b3["timeout"] as? Double, 5)
        let (_, b4) = try req("type secret --id login.password")
        XCTAssertEqual(b4["value"] as? String, "secret")
        XCTAssertNil(b4["text"], "typed value never becomes a selector")
        XCTAssertNil(try FlowStep.parse(line: "snap home")!.runnerRequest(defaultBundleId: nil))
        XCTAssertThrowsError(try FlowStep.parse(line: "tap")!.runnerRequest(defaultBundleId: nil))
        XCTAssertThrowsError(try FlowStep.parse(line: "launch")!.runnerRequest(defaultBundleId: nil))
    }

    func testVariables() throws {
        let step = try XCTUnwrap(try FlowStep.parse(line: "type ${EMAIL} --id login.${FIELD}", line: 3))
        let s = try step.substituting(["EMAIL": "me@x.com", "FIELD": "email"])
        XCTAssertEqual(s.positional, ["me@x.com"])
        XCTAssertEqual(s.option("id"), "login.email")
        XCTAssertThrowsError(try step.substituting([:])) { e in XCTAssertTrue("\(e)".contains("undefined variable ${EMAIL}")) }
    }
}

final class FlowFileTests: XCTestCase {
    var home = ""

    override func setUp() {
        home = NSTemporaryDirectory() + "proofhome-\(UUID().uuidString)"
        setenv("PROOF_HOME", home, 1)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PROOF_HOME")
    }

    func testSaveLoadIncludeAndCycle() throws {
        _ = try Flow.save(name: "login", lines: ["tap --id onboarding.skip", "type ${EMAIL} --id login.email"], repo: "app", overwrite: false)
        _ = try Flow.save(name: "checkout", lines: ["include login", "", "# comment", "tap --id cart.pay", "snap paid"], repo: "app", overwrite: false)
        let f = try Flow.load("checkout", repo: "app")
        XCTAssertEqual(f.steps.map(\.action), ["tap", "type", "tap", "snap"])
        XCTAssertEqual(Flow.list(repo: "app"), ["checkout", "login"])
        XCTAssertThrowsError(try Flow.save(name: "login", lines: ["home"], repo: "app", overwrite: false))

        _ = try Flow.save(name: "a", lines: ["include b"], repo: "app", overwrite: true)
        _ = try Flow.save(name: "b", lines: ["include a"], repo: "app", overwrite: true)
        XCTAssertThrowsError(try Flow.load("a", repo: "app")) { e in XCTAssertTrue("\(e)".contains("too deep")) }
    }

    func testRecorder() throws {
        let ctx = Context(root: "/r", mainRoot: "/r", repo: "app", branch: "feat/x", config: RepoConfig())
        XCTAssertNil(Recorder.state())
        Recorder.record(FlowStep(action: "home"), repo: "app")
        XCTAssertNil(Recorder.state(), "nothing recorded when not recording")
        try Recorder.start(ctx)
        Recorder.record(try FlowStep.parse(line: "tap --id a")!, repo: "app")
        Recorder.record(try FlowStep.parse(line: "tap --id other-repo")!, repo: "other")
        Recorder.record(try FlowStep.parse(line: #"type "hi there" --id b"#)!, repo: "app")
        Recorder.record(try FlowStep.parse(line: "tap --id oops")!, repo: "app")
        XCTAssertEqual(try Recorder.undo(1).lines, ["tap --id a", #"type "hi there" --id b"#])
        let s = try XCTUnwrap(Recorder.stop())
        XCTAssertEqual(s.branch, "feat/x")
        XCTAssertNil(Recorder.state())
    }

    func testEventsLog() throws {
        let ctx = Context(root: "/r", mainRoot: "/r", repo: "app", branch: "main", config: RepoConfig())
        Events.append(ProofEvent(kind: "step", name: "tap --id a", status: "started", flow: "login", index: 1, total: 2), ctx: ctx)
        Events.append(ProofEvent(kind: "step", name: "tap --id a", status: "ok", duration: 0.4, flow: "login", index: 1, total: 2), ctx: ctx)
        let events = Events.load(ctx.sessionDir)
        XCTAssertEqual(events.map(\.status), ["started", "ok"])
        XCTAssertEqual(events.last?.index, 1)
        let current = try XCTUnwrap(Events.current())
        XCTAssertEqual(current.branch, "main")
    }

    func testFlowReportText() {
        var r = FlowRunReport(flow: "login", branch: "feat/x", sha: "abc", steps: [
            StepResult(index: 1, line: "launch", status: "ok", duration: 0.8),
            StepResult(index: 2, line: "tap --id login.submit", status: "failed", error: "element not found: id=login.submit"),
            StepResult(index: 3, line: "expect --id home.title", status: "skipped"),
        ], failureSnap: "/tmp/f.png", video: nil, duration: 2)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.failedAt, 2)
        let text = r.text
        XCTAssertTrue(text.hasPrefix("FLOW login · feat/x (abc) · 1/3 ok · FAILED at step 2 · 2.0s"))
        XCTAssertTrue(text.contains("✗  2 tap --id login.submit"))
        XCTAssertTrue(text.contains("element not found"))
        XCTAssertTrue(text.contains("-  3 expect --id home.title"))
        r.steps[1].status = "ok"; r.steps[2].status = "ok"
        XCTAssertTrue(r.ok)
    }
}

final class HitTestTests: XCTestCase {
    let nodes: [UINode] = [
        UINode(type: "app", depth: 0, frame: [0, 0, 400, 800], label: "Tempo"),
        UINode(type: "cell", depth: 1, frame: [0, 100, 400, 60], label: "Workout"),
        UINode(type: "text", depth: 2, frame: [10, 110, 200, 20], label: "Workout"),
        UINode(type: "button", depth: 1, frame: [20, 600, 360, 44], id: "login.submit", label: "Log in"),
        UINode(type: "button", depth: 1, frame: [20, 660, 170, 44], label: "Edit"),
        UINode(type: "button", depth: 1, frame: [210, 660, 170, 44], label: "Edit"),
        UINode(type: "image", depth: 1, frame: [0, 300, 400, 200]),
    ]

    func testHitPrefersSmallestInteractive() {
        XCTAssertEqual(UITree.hitTest(nodes, x: 50, y: 120), 1, "cell beats the text inside it")
        XCTAssertEqual(UITree.hitTest(nodes, x: 100, y: 620), 3)
        XCTAssertNil(UITree.hitTest(nodes, x: 100, y: 400), "unnamed image is not a target")
    }

    func testSelectorPreference() {
        XCTAssertEqual(UITree.selectorTokens(for: 3, in: nodes), ["--id", "login.submit"])
        XCTAssertEqual(UITree.selectorTokens(for: 1, in: nodes), ["--type", "cell", "--label", "Workout"])
        XCTAssertEqual(UITree.selectorTokens(for: 5, in: nodes), ["--type", "button", "--label", "Edit", "--index", "1"])
        XCTAssertEqual(UITree.selectorTokens(for: 6, in: nodes), ["--x", "200", "--y", "400"])
    }
}

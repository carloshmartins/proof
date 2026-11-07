import XCTest
@testable import ProofKit

/// The JSON examples in the docs (`docs/examples/json/*.json`) are encoded from the real report types here,
/// so the docs can't drift from what `--json` prints.
///
/// - `swift test` fails if an example no longer matches its type.
/// - `PROOF_UPDATE_DOCS=1 swift test --filter DocExamplesTests` rewrites them (`make docs-reference` does this).
final class DocExamplesTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/examples/json")

    func testExamples() throws {
        let update = ProcessInfo.processInfo.environment["PROOF_UPDATE_DOCS"] == "1"
        if update { try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true) }
        for (name, value) in Self.examples {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try enc.encode(AnyEncodable(value))
            let url = Self.dir.appendingPathComponent(name + ".json")
            if update {
                try (String(decoding: data, as: UTF8.self) + "\n").write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            guard let existing = FileManager.default.contents(atPath: url.path) else {
                XCTFail("missing docs/examples/json/\(name).json · run make docs-reference"); continue
            }
            let a = try JSONSerialization.jsonObject(with: data) as? NSObject
            let b = try JSONSerialization.jsonObject(with: existing) as? NSObject
            XCTAssertEqual(a, b, "docs/examples/json/\(name).json is out of date · run make docs-reference")
        }
    }

    // MARK: - Examples (fictional app "Tempo"; never real paths or names)

    static let session = "~/.proof/sessions/Tempo/feat_presets"

    static var examples: [(String, any Encodable)] {
        let buildFailed = BriefResult(
            status: "failed", action: "build",
            errors: [Diagnostic(kind: "error", file: "Modules/Timer/Sources/TimerView.swift", line: 42, column: 17,
                                message: "cannot find 'viewModel' in scope")],
            warningCount: 3, duration: 38.2)
        var testFailed = BriefResult(status: "failed", action: "test", duration: 61.4)
        testFailed.tests = TestSummary(passed: 181, failed: 1, skipped: 2, failures: [
            TestFailure(test: "TimerTests/testPresetPersists", file: "Tests/TimerTests.swift", line: 57,
                        message: "XCTAssertEqual failed: (\"25\") is not equal to (\"15\")")])
        var passed = BriefResult(status: "succeeded", action: "test", duration: 58.9)
        passed.tests = TestSummary(passed: 182, failed: 0, skipped: 2)

        let stack = StackReport(
            branches: [BranchRun(branch: "feat/models", sha: "a1b2c3d", result: passed, pr: 41),
                       BranchRun(branch: "feat/presets", sha: "8a6c41e", result: testFailed, pr: 42)],
            introduced: ["TimerTests/testPresetPersists": "feat/presets"],
            skipped: [])

        let flow = FlowRunReport(
            flow: "start-timer", branch: "feat/presets", sha: "8a6c41e",
            steps: [StepResult(index: 1, line: "launch", status: "ok", duration: 2.1),
                    StepResult(index: 2, line: "tap --id timer.start", status: "ok", duration: 0.4),
                    StepResult(index: 3, line: "expect --id timer.running", status: "failed", duration: 5.0,
                               error: "no element matching #timer.running within 5s"),
                    StepResult(index: 4, line: "snap running", status: "skipped")],
            failureSnap: session + "/snaps/start-timer-failed.png", video: nil, duration: 7.6)

        var okFlow = flow
        okFlow.steps = okFlow.steps.map { var s = $0; s.status = "ok"; s.error = nil; return s }
        okFlow.failureSnap = nil
        var stackFlow = StackFlowReport(flow: "start-timer", runs: [
            BranchFlowRun(branch: "feat/models", sha: "a1b2c3d", build: "succeeded", flow: okFlow,
                          changedScreens: ["running": 0], comparedWith: "develop", pr: 41)])
        stackFlow = StackFlowReport(flow: stackFlow.flow, runs: stackFlow.runs + [
            BranchFlowRun(branch: "feat/presets", sha: "8a6c41e", build: "failed",
                          buildErrors: buildFailed.errors, pr: 42)])

        let ax = AXScanReport(findings: [
            AXFinding(file: "Modules/Timer/Sources/PresetsView.swift", line: 23, kind: "swiftui", control: "Button",
                      snippet: "Button(\"Add preset\") { model.add() }")], filesScanned: 148)

        let pr = PRCommentsReport(
            number: 42, title: "Add timer presets", url: "https://github.com/example/tempo/pull/42",
            threads: [.init(path: "Modules/Timer/Sources/PresetsView.swift", line: 23, outdated: false, resolved: false,
                            comments: [.init(author: "reviewer", body: "Add an accessibility identifier here.")])],
            resolvedHidden: 1,
            reviews: [.init(author: "reviewer", state: "CHANGES_REQUESTED", body: "Close, a couple of things.")],
            comments: [])

        let stop = StopReport(stopped: [ActiveRun(pid: 4242, command: "flow run start-timer --stack", repo: "Tempo",
                                                  branch: "feat/presets", started: Date(timeIntervalSinceReferenceDate: 815_000_000))])

        return [
            ("message", MessageReport("tapped button #timer.start \"Start\"")),
            ("message-failed", MessageReport(ok: false, "no element matching #timer.running within 5s")),
            ("build-failed", buildFailed),
            ("test-failed", testFailed),
            ("test-stack", stack),
            ("flow-run", flow),
            ("flow-run-stack", stackFlow),
            ("ax-scan", ax),
            ("pr-comments", pr),
            ("stop", stop),
            ("ui-tree", TreeExample(
                nodes: [UINode(type: "button", depth: 2, frame: [16, 680, 361, 50], id: "timer.start", label: "Start", enabled: true),
                        UINode(type: "button", depth: 2, frame: [16, 740, 361, 50], id: "timer.presets", label: "Presets", enabled: true)],
                screen: ScreenSize(width: 393, height: 852),
                rendered: "button #timer.start \"Start\"\nbutton #timer.presets \"Presets\"")),
            ("packet", PacketReport(markdown: "# Tempo · feat/presets (8a6c41e)\n…", html: "<!doctype html>…",
                                    summary: "packet → \(session)/report.html")),
        ]
    }

    /// Mirrors `proof ui tree --json` (TreeReport lives in the executable target).
    struct TreeExample: Encodable { let nodes: [UINode]; let screen: ScreenSize?; let rendered: String }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

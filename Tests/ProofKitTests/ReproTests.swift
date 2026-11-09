import XCTest
@testable import ProofKit

final class ReproTests: XCTestCase {
    func flow(_ text: String) throws -> Flow { try Flow.parse(text, name: "checkout") }

    func testExportIsSelfContainedWithAHeader() throws {
        let f = try flow("launch\ntype ${EMAIL} --id login.email\ntap --id login.submit\ntype ${EMAIL} --id x")
        XCTAssertEqual(Repro.variables(f), ["EMAIL"])
        let text = Repro.export(f, branch: "main", sha: "abc1234", device: "iPhone 16 · iOS 26.1", markdown: true)
        XCTAssertTrue(text.hasPrefix("```flow\n# proof flow checkout\n# recorded on main (abc1234) · iPhone 16 · iOS 26.1\n# needs --var EMAIL=…"))
        XCTAssertTrue(text.hasSuffix("tap --id login.submit\ntype ${EMAIL} --id x\n```"))
        XCTAssertEqual(Repro.extractFlow(markdown: "Broken:\n\n" + text)?.components(separatedBy: "\n").last, "type ${EMAIL} --id x")
    }

    func testExtractsFlowFromAnIssue() {
        let body = """
        The app crashes.

        ```swift
        let x = 1
        ```

        ```
        launch
        tap --id buy
        ```
        """
        XCTAssertEqual(Repro.extractFlow(markdown: body), "launch\ntap --id buy", "a plain block made only of steps")
        XCTAssertNil(Repro.extractFlow(markdown: "no code here"))
        XCTAssertNil(Repro.extractFlow(markdown: "```\nnot a step\n```"))
        XCTAssertEqual(Repro.extractFlow(markdown: "```\nlaunch\n```\n```flow\nhome\n```"), "home", "a flow block wins")
    }

    func testIssueNumbers() {
        XCTAssertEqual(Repro.issueNumber("123"), 123)
        XCTAssertEqual(Repro.issueNumber("#7"), 7)
        XCTAssertEqual(Repro.issueNumber("https://github.com/acme/app/issues/42#issuecomment-1"), 42)
        XCTAssertNil(Repro.issueNumber("checkout.flow"))
    }

    func testReportVerdicts() {
        let failed = FlowRunReport(flow: "issue-7", branch: "main", sha: "abc", steps: [
            StepResult(index: 1, line: "launch", status: "ok"),
            StepResult(index: 2, line: "tap --id buy", status: "failed", error: "app crashed: EXC_BAD_ACCESS at Cart.swift:9"),
        ], failureSnap: nil, video: nil, duration: 1)
        let r = ReproReport(source: "issue #7", flow: failed)
        XCTAssertTrue(r.reproduced)
        XCTAssertTrue(r.text.hasPrefix("REPRODUCED issue #7 · step 2 tap --id buy — app crashed: EXC_BAD_ACCESS at Cart.swift:9"))
        let passed = FlowRunReport(flow: "f", branch: "main", sha: "abc", steps: [StepResult(index: 1, line: "launch", status: "ok")],
                                   failureSnap: nil, video: nil, duration: 1)
        XCTAssertTrue(ReproReport(source: "f.flow", flow: passed).text.hasPrefix("NOT REPRODUCED f.flow · all 1 steps passed on main (abc)"))
    }
}

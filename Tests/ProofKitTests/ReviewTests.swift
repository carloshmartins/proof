import XCTest
@testable import ProofKit

final class ReviewTests: XCTestCase {
    func testDecodesGhPRView() throws {
        let json = #"{"number":42,"title":"Add presets","url":"https://github.com/o/r/pull/42","headRefName":"feat/presets","baseRefName":"main","headRefOid":"b7fd4fc1e2"}"#
        let info = try JSONDecoder().decode(Review.PRInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.baseRefName, "main")
        XCTAssertEqual(Review.sessionBranch(info.number), "pr-42")
    }

    func testReportText() {
        var r = ReviewReport(number: 42, title: "Add presets", url: "u", headBranch: "feat/presets", base: "main", sha: "b7fd4fc")
        r.build = BriefResult(status: "succeeded", action: "build", duration: 41)
        let flow = FlowRunReport(flow: "home", branch: "pr-42", sha: "b7fd4fc",
                                 steps: [StepResult(index: 1, line: "launch", status: "ok")], failureSnap: nil, video: nil, duration: 3)
        r.flows = [.init(flow: flow, changedScreens: ["home": 3, "settings": 0])]
        r.packet = "/tmp/report.html"
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.text, """
        REVIEW #42 Add presets · feat/presets → main (b7fd4fc)
        BUILD SUCCEEDED · 41.0s
        ✓ flow home  1/1 steps
            screens changed vs main: home (3 lines)
        report → /tmp/report.html
        the simulator now has #42's app; `proof run` puts yours back
        """)
    }

    func testNoFlowsSaysHowToGetScreens() {
        var r = ReviewReport(number: 7, title: "t", url: "u", headBranch: "h", base: "main", sha: "abc")
        r.build = BriefResult(status: "succeeded", action: "build")
        XCTAssertTrue(r.text.contains("no flows to replay"))
        r.build = BriefResult(status: "failed", action: "build")
        XCTAssertFalse(r.ok)
        XCTAssertFalse(r.text.contains("simulator now has"))
    }
}

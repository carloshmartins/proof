import XCTest
@testable import ProofKit

final class StackTests: XCTestCase {
    let pulls = [
        PullRef(number: 1, headRefName: "feat/model", baseRefName: "main"),
        PullRef(number: 2, headRefName: "feat/service", baseRefName: "feat/model"),
        PullRef(number: 3, headRefName: "feat/ui", baseRefName: "feat/service"),
        PullRef(number: 9, headRefName: "other", baseRefName: "main"),
    ]

    func testResolvesWholeStackFromMiddle() {
        XCTAssertEqual(StackResolver.resolve(current: "feat/service", trunk: "main", pulls: pulls),
                       ["feat/model", "feat/service", "feat/ui"])
    }

    func testResolvesFromTopAndBottom() {
        XCTAssertEqual(StackResolver.resolve(current: "feat/ui", trunk: "main", pulls: pulls).count, 3)
        XCTAssertEqual(StackResolver.resolve(current: "feat/model", trunk: "main", pulls: pulls).count, 3)
    }

    func testBranchWithoutPRIsItsOwnStack() {
        XCTAssertEqual(StackResolver.resolve(current: "wip", trunk: "main", pulls: pulls), ["wip"])
    }

    func testStopsAtFork() {
        var forked = pulls
        forked.append(PullRef(number: 4, headRefName: "feat/ui-alt", baseRefName: "feat/service"))
        XCTAssertEqual(StackResolver.resolve(current: "feat/model", trunk: "main", pulls: forked), ["feat/model", "feat/service"])
    }

    func testCycleDoesNotHang() {
        let cyclic = [PullRef(number: 1, headRefName: "a", baseRefName: "b"), PullRef(number: 2, headRefName: "b", baseRefName: "a")]
        XCTAssertFalse(StackResolver.resolve(current: "a", trunk: "main", pulls: cyclic).isEmpty)
    }

    func testIntroducedMapPointsAtLowestFailingBranch() {
        func run(_ b: String, failing: [String], buildError: Bool = false) -> BranchRun {
            var r = BriefResult(status: failing.isEmpty && !buildError ? "succeeded" : "failed", action: "test")
            var t = TestSummary()
            t.passed = 5
            t.failed = failing.count
            t.failures = failing.map { TestFailure(test: $0) }
            r.tests = t
            if buildError { r.errors = [Diagnostic(kind: "error", file: "A.swift", line: 1, column: 1, message: "x")] }
            return BranchRun(branch: b, sha: "abc", result: r)
        }
        let runs = [run("a", failing: []), run("b", failing: ["T/one"]), run("c", failing: ["T/one", "T/two"])]
        let map = StackReport.introducedMap(runs)
        XCTAssertEqual(map["T/one"], "b")
        XCTAssertEqual(map["T/two"], "c")
        let report = StackReport(branches: runs, introduced: map, skipped: [])
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.text.contains("FAIL T/one  (from b)"))
        XCTAssertTrue(report.text.contains("FAIL T/two  ← introduced here"))
    }
}

final class SimulatorTests: XCTestCase {
    let json = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-18-2":[{"udid":"OLD","name":"iPhone 16","state":"Shutdown","isAvailable":true}],
      "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"udid":"NEW","name":"iPhone 16","state":"Shutdown","isAvailable":true},
                                                     {"udid":"BOOT","name":"iPad Air","state":"Booted","isAvailable":true}],
      "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"udid":"W","name":"Watch","state":"Booted","isAvailable":true}]
    }}
    """

    func testPrefersNewestRuntimeForName() {
        let sims = Simulators.parse(simctlJSON: json)
        XCTAssertEqual(sims.count, 3, "non-iOS runtimes ignored")
        XCTAssertEqual(Simulators.pick("iPhone 16", from: sims)?.udid, "NEW")
    }

    func testDefaultsToBootedAndAcceptsUDID() {
        let sims = Simulators.parse(simctlJSON: json)
        XCTAssertEqual(Simulators.pick(nil, from: sims)?.udid, "BOOT")
        XCTAssertEqual(Simulators.pick("OLD", from: sims)?.udid, "OLD")
        XCTAssertNil(Simulators.pick("iPhone 99", from: sims))
    }
}

final class TreeTests: XCTestCase {
    func testRenderAndAudit() throws {
        let response: [String: Any] = ["nodes": [
            ["type": "app", "depth": 0, "label": "Tempo"],
            ["type": "button", "depth": 1, "id": "login.submit", "label": "Log in", "enabled": false],
            ["type": "textfield", "depth": 1, "placeholder": "Email"],
            ["type": "text", "depth": 1, "label": "Welcome"],
        ]]
        let nodes = try UITree.decode(response)
        XCTAssertEqual(UITree.render(nodes), """
        app "Tempo"
          button #login.submit "Log in" [disabled]
          textfield (Email)
          text "Welcome"
        """)
        XCTAssertEqual(UITree.missingIdentifiers(nodes).map(\.type), ["textfield"])
        XCTAssertEqual(UITree.render(nodes, interactiveOnly: true), "button #login.submit \"Log in\" [disabled]\ntextfield (Email)")
    }

    func testLineDiff() {
        let d = LineDiff.diff(["a", "b", "c"], ["a", "c", "d"])
        XCTAssertEqual(d, ["- b", "+ d"])
        XCTAssertTrue(LineDiff.diff(["x"], ["x"]).isEmpty)
    }
}

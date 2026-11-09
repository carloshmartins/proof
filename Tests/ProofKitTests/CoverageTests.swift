import XCTest
@testable import ProofKit

final class CoverageTests: XCTestCase {
    func testChangedLinesFromAZeroContextDiff() {
        let diff = """
        diff --git a/App/Math.swift b/App/Math.swift
        --- a/App/Math.swift
        +++ b/App/Math.swift
        @@ -2,0 +3,3 @@ func classify
        +    if n < 0 {
        @@ -10 +13 @@
        -old
        +new
        @@ -20,2 +22,0 @@
        diff --git a/App/Gone.swift b/App/Gone.swift
        --- a/App/Gone.swift
        +++ /dev/null
        @@ -1,3 +0,0 @@
        """
        XCTAssertEqual(Coverage.changedLines(diff: diff), ["App/Math.swift": [3, 4, 5, 13]])
    }

    func testLineCountsKeepOnlyExecutableLines() {
        let json = #"{"/tmp/App/Math.swift":[{"executionCount":1,"isExecutable":true,"line":1},{"executionCount":0,"isExecutable":true,"line":3},{"isExecutable":false,"line":4}]}"#
        XCTAssertEqual(Coverage.lineCounts(json: json), [1: 1, 3: 0])
    }

    func testAppFilesLeaveTestBundlesOut() {
        let json = #"{"targets":[{"name":"App.app","files":[{"path":"/r/App/Math.swift"}]},{"name":"AppTests.xctest","files":[{"path":"/r/Tests/MathTests.swift"}]}]}"#
        XCTAssertEqual(Coverage.appFiles(reportJSON: json), ["/r/App/Math.swift"])
    }

    func testReport() {
        let r = Coverage.report(base: "main",
                                changed: ["App/Math.swift": [1, 2, 3, 4, 5, 6, 9], "README.md": [1], "App/Other.swift": [7]],
                                coverage: ["App/Math.swift": [1: 2, 2: 1, 3: 0, 4: 0, 5: 0, 6: 3], "App/Other.swift": [7: 1]])
        XCTAssertEqual(r.executable, 7)
        XCTAssertEqual(r.covered, 4)
        XCTAssertEqual(r.percent, 57)
        XCTAssertEqual(r.text, """
        COVERAGE 4 of 7 changed lines run by tests (57%) vs main
        untested  App/Math.swift: 3-5
        """)
        XCTAssertEqual(ChangedCoverage.ranges([9, 1, 2, 3, 5]), "1-3, 5, 9")
        XCTAssertEqual(Coverage.report(base: "main", changed: [:], coverage: [:]).text, "COVERAGE no changed code lines vs main")
    }
}

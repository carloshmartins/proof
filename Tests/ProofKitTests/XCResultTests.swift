import XCTest
@testable import ProofKit

final class XCResultTests: XCTestCase {
    func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesTestCasesAndFailures() throws {
        let cases = XCResult.parseTests(json: try fixture("xcresult-tests"))
        XCTAssertEqual(cases.map(\.name), ["FlakyTests/testAlwaysFails", "FlakyTests/testAttachment", "FlakyTests/testFine"])
        XCTAssertEqual(cases.map(\.result), ["Failed", "Failed", "Passed"])
        XCTAssertEqual(cases[0].failures, [XCResult.Failure(file: "FlakyTests.swift", line: 4,
                                                             message: #"XCTAssertEqual failed: ("1") is not equal to ("2") - always broken"#)])
    }

    func testAttachmentsManifest() throws {
        let m = XCResult.parseManifest(json: try fixture("xcresult-attachments"))
        let files = try XCTUnwrap(m["FlakyTests/testAttachment"])
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].name.hasPrefix("notes_0_"))
        XCTAssertTrue(files[0].exported.hasSuffix(".txt"))
    }

    func testNormalize() {
        XCTAssertEqual(XCResult.normalize("Suite/testX()"), "Suite/testX")
        XCTAssertEqual(XCResult.normalize("Suite/progressSmoothing()"), "Suite/progressSmoothing()", "Swift Testing keeps ()")
        XCTAssertEqual(XCResult.parseFailure("no location here").file, nil)
    }

    func testApplyMakesFailuresExactAndAddsMissedOnes() {
        var brief = BriefResult(status: "failed", action: "test")
        var t = TestSummary(passed: 1, failed: 1)
        t.failures = [TestFailure(test: "FlakyTests/testAlwaysFails", file: "Tests/FlakyTests.swift", line: 4, message: "XCTAssertEqual failed…")]
        brief.tests = t
        let cases = [
            XCResult.TestCase(name: "FlakyTests/testAlwaysFails", result: "Failed",
                              failures: [.init(file: "FlakyTests.swift", line: 4, message: "XCTAssertEqual failed: whole message")]),
            XCResult.TestCase(name: "FlakyTests/testCrashed", result: "Failed",
                              failures: [.init(file: nil, line: nil, message: "Crash: Tests (123) EXC_BREAKPOINT")]),
            XCResult.TestCase(name: "FlakyTests/testFine", result: "Passed", failures: []),
        ]
        XCResult.apply(cases, attachments: ["FlakyTests/testAlwaysFails": ["/r/notes.txt"]], to: &brief)
        let f = brief.tests!.failures
        XCTAssertEqual(f.map(\.test), ["FlakyTests/testAlwaysFails", "FlakyTests/testCrashed"])
        XCTAssertEqual(f[0].message, "XCTAssertEqual failed: whole message")
        XCTAssertEqual(f[0].file, "Tests/FlakyTests.swift", "the log's repo-relative path is kept")
        XCTAssertEqual(f[0].attachments, ["/r/notes.txt"])
        XCTAssertEqual(brief.tests!.failed, 2)
        XCTAssertTrue(brief.text.contains("attachment → /r/notes.txt"))
    }

    func testFlakyTestsStayFlaky() {
        var brief = BriefResult(status: "succeeded", action: "test")
        var t = TestSummary(passed: 1)
        t.flaky = [FlakyTest(test: "S/testX", failedRuns: 1, runs: 2)]
        brief.tests = t
        XCResult.apply([.init(name: "S/testX", result: "Failed", failures: [])], attachments: [:], to: &brief)
        XCTAssertEqual(brief.tests!.failed, 0)
        XCTAssertEqual(brief.status, "succeeded")
    }
}

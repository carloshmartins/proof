import XCTest
@testable import ProofKit

final class WarningsTests: XCTestCase {
    func w(_ file: String?, _ line: Int, _ message: String) -> Diagnostic {
        Diagnostic(kind: "warning", file: file, line: line, column: 5, message: message)
    }

    func testAddedIgnoresLineNumbersAndCountsRepeats() {
        let base = [w("A.swift", 10, "unused variable 'x'"), w("B.swift", 3, "deprecated")]
        let current = [w("A.swift", 14, "unused variable 'x'"), w("A.swift", 20, "unused variable 'x'"),
                       w("B.swift", 3, "deprecated"), w("C.swift", 1, "never mutated")]
        let added = Warnings.added(current: current, base: base)
        XCTAssertEqual(added.map(\.file), ["A.swift", "C.swift"], "one extra 'x' warning and the C.swift one")
        XCTAssertEqual(added.first?.line, 20)
        XCTAssertTrue(Warnings.added(current: base, base: current).isEmpty, "fixing warnings adds none")
        XCTAssertTrue(Warnings.added(current: base, base: base).isEmpty)
    }

    func testMergeKeepsWarningsOfFilesNotRecompiled() {
        let previous = [w("A.swift", 1, "old a"), w("B.swift", 1, "b stays"), w(nil, 0, "project warning")]
        let fresh = [w("A.swift", 2, "new a")]
        let merged = Warnings.merge(previous: previous, fresh: fresh, compiled: ["A.swift"])
        XCTAssertEqual(Set(merged.map(\.message)), ["b stays", "new a"], "A.swift replaced, B.swift kept, file-less replaced")
        XCTAssertEqual(Warnings.merge(previous: previous, fresh: [], compiled: ["A.swift", "B.swift"]).count, 0)
    }

    func testCompiledFilesFromXcodebuildOutput() {
        let log = """
        SwiftCompile normal arm64 /Users/me/App/Sources/A.swift (in target 'App' from project 'App')
        SwiftCompile normal arm64 Compiling\\ My\\ View.swift /Users/me/App/Sources/My\\ View.swift (in target 'App')
        CompileC /tmp/B.o /Users/me/App/Legacy/B.m normal arm64 objective-c
        Ld /tmp/App normal
        """
        XCTAssertEqual(Warnings.compiledFiles(log: log, root: "/Users/me/App"),
                       ["Sources/A.swift", "Sources/My View.swift", "Legacy/B.m"])
    }

    func testRecordSkipsFailedBuildsAndSaves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var failed = BriefResult(status: "failed", action: "build")
        failed.errors = [Diagnostic(kind: "error", file: "A.swift", line: 1, column: 1, message: "boom")]
        XCTAssertNil(Warnings.record(failed, allWarnings: [w("A.swift", 1, "x")], log: "", root: "/r", sessionDir: dir))
        XCTAssertNil(Warnings.load(sessionDir: dir))
        let ok = BriefResult(status: "succeeded", action: "build")
        Warnings.record(ok, allWarnings: [w("A.swift", 1, "x")], log: "", root: "/r", sessionDir: dir)
        XCTAssertEqual(Warnings.load(sessionDir: dir)?.map(\.message), ["x"])
    }

    func testRendering() {
        var r = BriefResult(status: "succeeded", action: "build", warningCount: 3, duration: 1)
        r.newWarnings = [w("Sources/A.swift", 20, "unused variable 'x'")]
        r.warningsBase = "main"
        XCTAssertEqual(r.text, """
        BUILD SUCCEEDED · 3 warnings · 1 new vs main · 1.0s
        new    Sources/A.swift:20:5  unused variable 'x'
        """)
        r.newWarnings = []
        XCTAssertTrue(r.text.hasPrefix("BUILD SUCCEEDED · 3 warnings · no new warnings vs main"))
    }
}

import XCTest
@testable import ProofKit

final class CrashesTests: XCTestCase {
    func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "crash", withExtension: "ips", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesASwiftTrapFromASimulatorCrashReport() throws {
        let r = try XCTUnwrap(Crashes.parse(ips: try fixture(), path: "/tmp/CrashApp.ips"))
        XCTAssertEqual(r.app, "CrashApp")
        XCTAssertEqual(r.bundleId, "dev.proof.CrashApp")
        XCTAssertEqual(r.exception, "EXC_BREAKPOINT (SIGTRAP)")
        XCTAssertTrue(r.isSwiftTrap)
        let app = try XCTUnwrap(r.appFrame)
        XCTAssertEqual(app.location, "App.swift:14")
        XCTAssertEqual(app.symbol, "closure #1 in ContentView.body.getter")
        XCTAssertFalse(r.frames[0].inApp, "libswiftCore is not app code")
        XCTAssertEqual(r.summary, "app crashed: EXC_BREAKPOINT (SIGTRAP) at App.swift:14")
        XCTAssertTrue(r.text.contains("▸ CrashApp.debug.dylib  closure #1 in ContentView.body.getter  (App.swift:14)"), r.text)
        XCTAssertTrue(r.text.hasPrefix("CRASH CrashApp · EXC_BREAKPOINT (SIGTRAP) · Swift runtime trap\nat App.swift:14"))
    }

    func testGarbageIsNotACrash() {
        XCTAssertNil(Crashes.parse(ips: "not json\n{}", path: "x"))
        XCTAssertNil(Crashes.parse(ips: "{}", path: "x"))
    }

    func testFindsOnlyThisAppsRecentReports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = try fixture()
        try text.write(to: dir.appendingPathComponent("CrashApp-new.ips"), atomically: true, encoding: .utf8)
        try text.write(to: dir.appendingPathComponent(".CrashApp-partial.ips"), atomically: true, encoding: .utf8)
        try text.replacingOccurrences(of: "dev.proof.CrashApp", with: "other.app")
            .write(to: dir.appendingPathComponent("Other.ips"), atomically: true, encoding: .utf8)
        let old = dir.appendingPathComponent("CrashApp-old.ips")
        try text.write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: old.path)

        let found = Crashes.find(bundleId: "dev.proof.CrashApp", since: Date().addingTimeInterval(-60), dir: dir.path)
        XCTAssertEqual(found.map { ($0.path as NSString).lastPathComponent }, ["CrashApp-new.ips"])
    }

    func testAppGoneErrors() {
        XCTAssertTrue(Crashes.looksLikeAppGone("Failed to get matching snapshot: Application dev.proof.CrashApp is not running"))
        XCTAssertFalse(Crashes.looksLikeAppGone("id=login not found within 5s. Run `proof ui tree`"))
    }

    func testFlowReportShowsTheCrash() throws {
        var report = FlowRunReport(flow: "crash", branch: "main", sha: "abc", steps: [
            StepResult(index: 1, line: "tap --id crash.button", status: "failed", error: "app crashed: EXC_BREAKPOINT (SIGTRAP) at App.swift:14"),
        ], failureSnap: nil, video: nil, duration: 1)
        report.crash = Crashes.parse(ips: try fixture(), path: "/tmp/CrashApp.ips")
        XCTAssertTrue(report.text.contains("app crashed: EXC_BREAKPOINT (SIGTRAP) at App.swift:14"))
        XCTAssertTrue(report.text.contains("CRASH CrashApp"))
        XCTAssertTrue(report.text.contains("report → /tmp/CrashApp.ips"))
    }
}

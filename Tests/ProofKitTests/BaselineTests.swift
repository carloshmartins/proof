import XCTest
@testable import ProofKit

final class BaselineTests: XCTestCase {
    var home = ""

    override func setUp() {
        home = NSTemporaryDirectory() + "proof-baseline-\(UUID().uuidString)"
        setenv("PROOF_HOME", home, 1)
        try? FileManager.default.createDirectory(atPath: Flow.directory(repo: "Tempo"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        unsetenv("PROOF_HOME")
        try? FileManager.default.removeItem(atPath: home)
    }

    func writeFlow(_ name: String, _ text: String) throws {
        try text.write(toFile: Paths.join(Flow.directory(repo: "Tempo"), name + ".flow"), atomically: true, encoding: .utf8)
    }

    func snap(_ name: String, on branch: String) throws {
        let record = SnapRecord(name: name, screenshot: "/s.png", tree: "/s.txt", branch: branch, sha: "abc",
                                time: Date(), compareBranch: nil, diff: nil, missingIdentifiers: 0)
        let dir = Paths.session(repo: "Tempo", branch: branch)
        try Paths.ensureDir(Paths.join(dir, "snaps"))
        try Snaps.save(Snaps.load(sessionDir: dir) + [record], sessionDir: dir)
    }

    func testSnapNamesFollowIncludesAndVariables() throws {
        try writeFlow("open", "launch\nsnap home\n")
        try writeFlow("presets", "include open\ntap --id timer.presets\nsnap presets-${THEME}\n")
        let flow = try Flow.load("presets", repo: "Tempo")
        XCTAssertEqual(Baseline.snapNames(flow, vars: ["THEME": "dark"]), ["home", "presets-dark"])
    }

    func testMissingAndNeeded() throws {
        try writeFlow("presets", "launch\nsnap home\ntap --id timer.presets\nsnap presets\n")
        let flow = try Flow.load("presets", repo: "Tempo")
        XCTAssertEqual(Baseline.missing(flow, on: "main", repo: "Tempo"), ["home", "presets"])
        XCTAssertTrue(Baseline.isNeeded(flow, base: "main", current: "feat/a", repo: "Tempo", fresh: false))

        try snap("home", on: "main")
        XCTAssertEqual(Baseline.missing(flow, on: "main", repo: "Tempo"), ["presets"])
        XCTAssertTrue(Baseline.isNeeded(flow, base: "main", current: "feat/a", repo: "Tempo", fresh: false))

        try snap("presets", on: "main")
        XCTAssertFalse(Baseline.isNeeded(flow, base: "main", current: "feat/a", repo: "Tempo", fresh: false), "all snaps exist")
        XCTAssertTrue(Baseline.isNeeded(flow, base: "main", current: "feat/a", repo: "Tempo", fresh: true), "--fresh-baseline")
        XCTAssertFalse(Baseline.isNeeded(flow, base: "feat/a", current: "feat/a", repo: "Tempo", fresh: true), "same branch")
    }

    func testFlowWithoutSnapsNeverNeedsABaseline() throws {
        try writeFlow("tap", "launch\ntap --id timer.start\n")
        XCTAssertFalse(Baseline.isNeeded(try Flow.load("tap", repo: "Tempo"), base: "main", current: "feat/a", repo: "Tempo", fresh: true))
    }

    func testDisplayPath() {
        XCTAssertEqual(Paths.display(NSHomeDirectory() + "/.proof/worktrees/Tempo"), "~/.proof/worktrees/Tempo")
        XCTAssertEqual(Paths.display("/tmp/x"), "/tmp/x")
    }
}

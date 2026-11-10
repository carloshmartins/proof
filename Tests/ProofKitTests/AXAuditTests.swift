import XCTest
@testable import ProofKit

final class AXAuditTests: XCTestCase {
    func testDecodesRunnerIssuesAndRenders() {
        let response: [String: Any] = ["supported": true, "issues": [
            ["type": "hit-region", "summary": "Hit area is too small",
             "element": ["type": "button", "id": "star", "label": "Favourite", "frame": [10, 20, 12, 12]]],
            ["type": "contrast", "summary": "Contrast failed", "detail": "…",
             "element": ["type": "text", "id": "", "label": "Barely visible"]],
            ["summary": "no type: dropped"],
        ]]
        let (supported, issues) = AXAuditReport.decodeIssues(response)
        XCTAssertTrue(supported)
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].element?.frame, [10, 20, 12, 12])
        let report = AXAuditReport(supported: true, issues: issues,
                                   missingIdentifiers: [UINode(type: "button", depth: 0, label: "Skip")])
        XCTAssertFalse(report.clean)
        XCTAssertEqual(report.text, """
        AX AUDIT · 2 issues · 1 without identifier
        hit-region        button #star "Favourite"  Hit area is too small
        contrast          text "Barely visible"  Contrast failed
        without identifier:
        button "Skip"
        """)
    }

    func testOldSimulatorsSayWhatWasChecked() {
        let report = AXAuditReport(supported: false, issues: [], missingIdentifiers: [])
        XCTAssertTrue(report.clean)
        XCTAssertTrue(report.text.hasPrefix("AX AUDIT clean"))
        XCTAssertTrue(report.text.contains("needs an iOS 17"))
    }

    func testRunnerSourcesMatch() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? fm.removeItem(atPath: root) }
        let resources = Installer.Resources(root: Paths.join(root, "res"))
        try fm.createDirectory(atPath: Paths.join(resources.runner, "ProofRunnerUITests"), withIntermediateDirectories: true)
        try "a".write(toFile: Paths.join(resources.runner, "ProofRunnerUITests", "A.swift"), atomically: true, encoding: .utf8)
        let dest = Paths.join(root, "installed")
        XCTAssertFalse(Installer.runnerMatches(resources, runnerDest: dest), "nothing installed")
        try Installer.installRunner(resources, runnerDest: dest)
        XCTAssertTrue(Installer.runnerMatches(resources, runnerDest: dest))
        try "b".write(toFile: Paths.join(resources.runner, "ProofRunnerUITests", "A.swift"), atomically: true, encoding: .utf8)
        XCTAssertFalse(Installer.runnerMatches(resources, runnerDest: dest), "a newer proof ships different sources")
    }
}

import XCTest
@testable import ProofKit

final class InstallerTests: XCTestCase {
    var tmp = ""

    override func setUp() {
        tmp = Paths.canonical(NSTemporaryDirectory()) + "/installer-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: tmp) }

    /// Writes Runner/ProofRunner.xcodeproj and skill/proof/SKILL.md under `root`.
    func makeResources(_ root: String, skill: String = "skill v1") throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/Runner/ProofRunner.xcodeproj", withIntermediateDirectories: true)
        try "project".write(toFile: root + "/Runner/ProofRunner.xcodeproj/project.pbxproj", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: root + "/skill/proof", withIntermediateDirectories: true)
        try skill.write(toFile: root + "/skill/proof/SKILL.md", atomically: true, encoding: .utf8)
    }

    func touchExecutable(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
    }

    func testFindsResourcesInsideAppBundle() throws {
        let contents = tmp + "/Host.app/Contents"
        try makeResources(contents + "/Resources")
        try touchExecutable(contents + "/Helpers/proof")
        XCTAssertEqual(Installer.resources(executable: contents + "/Helpers/proof")?.root, contents + "/Resources")
    }

    func testFollowsSymlinkToBundledBinary() throws {
        let contents = tmp + "/Host.app/Contents"
        try makeResources(contents + "/Resources")
        try touchExecutable(contents + "/Helpers/proof")
        try FileManager.default.createDirectory(atPath: tmp + "/bin", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: tmp + "/bin/proof", withDestinationPath: contents + "/Helpers/proof")
        XCTAssertEqual(Installer.resources(executable: tmp + "/bin/proof")?.root, contents + "/Resources")
    }

    func testFindsCheckoutFromBuildFolder() throws {
        let repo = tmp + "/proof"
        try makeResources(repo)
        try touchExecutable(repo + "/.build/arm64-apple-macosx/release/proof")
        XCTAssertEqual(Installer.resources(executable: repo + "/.build/arm64-apple-macosx/release/proof")?.root, repo)
    }

    func testNoResourcesNearAStandaloneBinary() throws {
        try touchExecutable(tmp + "/bin/proof")
        XCTAssertNil(Installer.resources(executable: tmp + "/bin/proof"))
    }

    func testInstallCopiesRunnerAndSkillAndIsIdempotent() throws {
        let src = tmp + "/src"
        try makeResources(src)
        let runner = tmp + "/home/runner/src", skillDir = tmp + "/skills/proof"
        // A stale file from an older install disappears.
        try FileManager.default.createDirectory(atPath: runner, withIntermediateDirectories: true)
        try "old".write(toFile: runner + "/stale.swift", atomically: true, encoding: .utf8)

        let r = try Installer.install(Installer.Resources(root: src), runnerDest: runner, skillDir: skillDir)
        XCTAssertEqual(r.runner, runner)
        XCTAssertEqual(r.skill, skillDir + "/SKILL.md")
        XCTAssertTrue(Paths.exists(runner + "/ProofRunner.xcodeproj/project.pbxproj"))
        XCTAssertFalse(Paths.exists(runner + "/stale.swift"))
        XCTAssertEqual(try String(contentsOfFile: skillDir + "/SKILL.md", encoding: .utf8), "skill v1")
        XCTAssertTrue(r.text.contains("installed agent skill"))

        try "skill v2".write(toFile: src + "/skill/proof/SKILL.md", atomically: true, encoding: .utf8)
        _ = try Installer.install(Installer.Resources(root: src), runnerDest: runner, skillDir: skillDir)
        XCTAssertEqual(try String(contentsOfFile: skillDir + "/SKILL.md", encoding: .utf8), "skill v2")
        XCTAssertFalse(Paths.exists(runner + ".new"))
    }

    func testInstallRunnerLeavesTheSkillAlone() throws {
        let src = tmp + "/src"
        try makeResources(src)
        let runner = tmp + "/home/runner/src"
        try Installer.installRunner(Installer.Resources(root: src), runnerDest: runner)
        XCTAssertTrue(Paths.exists(runner + "/ProofRunner.xcodeproj/project.pbxproj"))
        XCTAssertFalse(Paths.exists(tmp + "/skills"))
    }

    func testInstallRefusesIncompleteResources() {
        XCTAssertThrowsError(try Installer.install(Installer.Resources(root: tmp + "/missing"),
                                                   runnerDest: tmp + "/r", skillDir: tmp + "/s"))
    }
}

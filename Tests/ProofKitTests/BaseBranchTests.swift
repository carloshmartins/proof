import XCTest
@testable import ProofKit

final class BaseBranchTests: XCTestCase {
    func testRemoteHeadParsing() {
        XCTAssertEqual(BaseBranch.fromRemoteHead("origin/develop"), "develop")
        XCTAssertEqual(BaseBranch.fromRemoteHead("refs/remotes/origin/main\n"), "main")
        XCTAssertEqual(BaseBranch.fromRemoteHead("origin/release/2.0"), "release/2.0")
        XCTAssertNil(BaseBranch.fromRemoteHead("origin/HEAD"))
        XCTAssertNil(BaseBranch.fromRemoteHead("develop"))
    }

    func testPickPrefersRemoteThenConventionalLocal() {
        XCTAssertEqual(BaseBranch.pick(remoteHead: "origin/develop", localBranches: ["main"]), "develop")
        XCTAssertEqual(BaseBranch.pick(remoteHead: nil, localBranches: ["feat/a", "master"]), "master")
        XCTAssertEqual(BaseBranch.pick(remoteHead: nil, localBranches: ["develop", "main"]), "main")
        XCTAssertNil(BaseBranch.pick(remoteHead: nil, localBranches: ["feat/a"]))
    }

    func testResolveCompare() {
        let pulls = [PullRef(number: 1, headRefName: "feat/a", baseRefName: "develop"),
                     PullRef(number: 2, headRefName: "feat/b", baseRefName: "feat/a")]
        XCTAssertEqual(BaseBranch.resolve("base", branch: "feat/b", trunk: "develop") { pulls }, "feat/a")
        XCTAssertEqual(BaseBranch.resolve("base", branch: "feat/a", trunk: "develop") { pulls }, "develop")
        XCTAssertEqual(BaseBranch.resolve("base", branch: "spike", trunk: "develop") { pulls }, "develop", "no PR → trunk")
        XCTAssertEqual(BaseBranch.resolve("release/2.0", branch: "feat/a", trunk: "develop") { XCTFail("no lookup"); return [] }, "release/2.0")
        XCTAssertNil(BaseBranch.resolve(nil, branch: "feat/a", trunk: "develop") { [] })
    }

    func testContextTrunkPrecedence() {
        var ctx = Context(root: "/r", mainRoot: "/r", repo: "app", branch: "feat/x", config: RepoConfig())
        XCTAssertEqual(ctx.trunk, "main", "nothing known")
        ctx.defaultBranch = "develop"
        XCTAssertEqual(ctx.trunk, "develop", "repo default")
        XCTAssertEqual(ctx.with(branch: "feat/y", root: "/wt").trunk, "develop", "kept for stack worktrees")
        ctx.config.trunk = "release/2.0"
        XCTAssertEqual(ctx.trunk, "release/2.0", "explicit config wins")
    }

    func testStackOnDevelopTrunk() {
        let pulls = [PullRef(number: 1, headRefName: "feat/a", baseRefName: "develop"),
                     PullRef(number: 2, headRefName: "feat/b", baseRefName: "feat/a"),
                     PullRef(number: 3, headRefName: "feat/c", baseRefName: "feat/b")]
        XCTAssertEqual(StackResolver.resolve(current: "feat/b", trunk: "develop", pulls: pulls), ["feat/a", "feat/b", "feat/c"])
    }

    func testStackOnReleaseBranchStopsAtItsBase() {
        // A stack into release/2.0 while the trunk is main: the walk down stops at release/2.0.
        let pulls = [PullRef(number: 1, headRefName: "fix/a", baseRefName: "release/2.0"),
                     PullRef(number: 2, headRefName: "fix/b", baseRefName: "fix/a")]
        let stack = StackResolver.resolve(current: "fix/b", trunk: "main", pulls: pulls)
        XCTAssertEqual(stack, ["fix/a", "fix/b"])
        XCTAssertEqual(BaseBranch.prBase(of: stack[0], pulls: pulls), "release/2.0")
    }

    func testDefaultBranchFromGit() throws {
        let dir = NSTemporaryDirectory() + "proof-base-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = { (args: [String]) throws in _ = try Shell.checked(["git"] + args, cwd: dir) }
        try git(["init", "-q", "-b", "trunk-less"])
        try git(["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"])
        XCTAssertNil(Git.defaultBranch(cwd: dir), "no remote head, no conventional branch")
        try git(["branch", "master"])
        XCTAssertEqual(Git.defaultBranch(cwd: dir), "master")
        try git(["update-ref", "refs/remotes/origin/develop", "HEAD"])
        try git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop"])
        XCTAssertEqual(Git.defaultBranch(cwd: dir), "develop")
    }
}

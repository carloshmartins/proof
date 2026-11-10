import Foundation

public struct PullRef: Codable, Equatable {
    public let number: Int
    public let headRefName: String
    public let baseRefName: String
    public init(number: Int, headRefName: String, baseRefName: String) {
        self.number = number; self.headRefName = headRefName; self.baseRefName = baseRefName
    }
}

/// Resolves a stack from open PRs by following base branches. Works with gh stack,
/// Graphite, spr or hand-made stacks: anything where each PR targets the one below it.
public enum StackResolver {
    /// Returns branches bottom → top (trunk excluded) that contain `current`.
    public static func resolve(current: String, trunk: String, pulls: [PullRef]) -> [String] {
        let byHead = Dictionary(pulls.map { ($0.headRefName, $0) }, uniquingKeysWith: { a, _ in a })
        var down: [String] = []
        var cursor = current
        var guardSet: Set<String> = []
        while cursor != trunk, let pr = byHead[cursor], guardSet.insert(cursor).inserted {
            down.append(cursor)
            cursor = pr.baseRefName
        }
        if down.isEmpty { down = current == trunk ? [] : [current] }
        var stack = Array(down.reversed())

        // Walk up while exactly one PR builds on the top branch.
        var top = stack.last ?? current
        while true {
            let children = pulls.filter { $0.baseRefName == top }
            guard children.count == 1, let child = children.first, !stack.contains(child.headRefName) else { break }
            stack.append(child.headRefName)
            top = child.headRefName
        }
        return stack
    }

    public static func fetchPulls(cwd: String) throws -> [PullRef] {
        let json = try Shell.checked(["gh", "pr", "list", "--state", "open", "--limit", "200",
                                      "--json", "number,headRefName,baseRefName"], cwd: cwd)
        return (try? JSONDecoder().decode([PullRef].self, from: Data(json.utf8))) ?? []
    }

    /// Branch → PR number, for stack reports.
    public static func numbers(_ pulls: [PullRef]) -> [String: Int] {
        Dictionary(pulls.map { ($0.headRefName, $0.number) }, uniquingKeysWith: { a, _ in a })
    }
}

public struct BranchRun: Codable {
    public let branch: String
    public let sha: String
    public let result: BriefResult
    public var pr: Int? = nil              // open PR for the branch, when known
}

public struct StackReport: Report, Decodable {
    public let branches: [BranchRun]
    public let introduced: [String: String]   // failing test or "build" -> first branch where it fails
    public let skipped: [String]

    public var ok: Bool { branches.allSatisfy { $0.result.succeeded } }

    public var text: String {
        var out: [String] = ["STACK \(branches.count) branch\(branches.count == 1 ? "" : "es") · \(ok ? "all green" : "failures")"]
        for run in branches {
            let r = run.result
            var line = (r.succeeded ? "✓ " : "✗ ") + "\(run.branch) (\(run.sha))"
            if let t = r.tests { line += "  \(t.passed) passed, \(t.failed) failed" }
            if !r.errors.isEmpty { line += "  \(r.errors.count) build error\(r.errors.count == 1 ? "" : "s")" }
            if let added = r.newWarnings, !added.isEmpty { line += "  +\(added.count) warning\(added.count == 1 ? "" : "s")" }
            out.append(line)
            for w in r.newWarnings?.prefix(3) ?? [] {
                out.append("    warn  \(BriefResult.location(w.file, w.line, w.column))\(w.message)  ← added here")
            }
            for e in r.errors.prefix(5) {
                out.append("    error \(BriefResult.location(e.file, e.line, e.column))\(e.message)")
            }
            for f in r.tests?.failures.prefix(8) ?? [] {
                let origin = introduced[f.test].map { $0 == run.branch ? "  ← introduced here" : "  (from \($0))" } ?? ""
                out.append("    FAIL \(f.test)\(f.message.map { "  \($0)" } ?? "")\(origin)")
            }
        }
        for s in skipped { out.append("- \(s) (skipped: stopped early)") }
        return out.joined(separator: "\n")
    }

    /// Maps each failure to the lowest branch where it first appears.
    public static func introducedMap(_ runs: [BranchRun]) -> [String: String] {
        var map: [String: String] = [:]
        for run in runs {
            if !run.result.errors.isEmpty, map["build"] == nil { map["build"] = run.branch }
            for f in run.result.tests?.failures ?? [] where map[f.test] == nil { map[f.test] = run.branch }
        }
        return map
    }
}

public struct StackOptions {
    public var branches: [String]? = nil
    public var from: String? = nil
    public var stopOnFail = false
    public var onlyTesting: [String] = []
    public var verbose = false
    public init() {}
}

public enum StackRunner {
    public static func branches(_ ctx: Context, explicit: [String]?) throws -> [String] {
        try plan(ctx, explicit: explicit).branches
    }

    /// The stack's branches bottom → top, their PR numbers (best effort for explicit lists), and the branch
    /// the bottom PR targets (the trunk, or e.g. `release/2.0` when the stack doesn't start from the trunk).
    public static func plan(_ ctx: Context, explicit: [String]?) throws -> (branches: [String], prs: [String: Int], base: String) {
        if let explicit, !explicit.isEmpty {
            let pulls = (try? StackResolver.fetchPulls(cwd: ctx.root)) ?? []
            return (explicit, StackResolver.numbers(pulls), BaseBranch.prBase(of: explicit[0], pulls: pulls) ?? ctx.trunk)
        }
        let pulls = try StackResolver.fetchPulls(cwd: ctx.root)
        let stack = StackResolver.resolve(current: ctx.branch, trunk: ctx.trunk, pulls: pulls)
        guard !stack.isEmpty else { throw ProofError.message("no stack found for \(ctx.branch). Pass --branches a,b,c") }
        return (stack, StackResolver.numbers(pulls), BaseBranch.prBase(of: stack[0], pulls: pulls) ?? ctx.trunk)
    }

    /// Tests every branch in one reusable worktree with its own DerivedData, so your
    /// checkout and agents' worktrees are untouched and builds stay incremental.
    public static func run(_ ctx: Context, _ opts: StackOptions) throws -> StackReport {
        let planned = try plan(ctx, explicit: opts.branches)
        var list = planned.branches
        if let from = opts.from, let i = list.firstIndex(of: from) { list = Array(list[i...]) }

        let wt = Paths.worktree(repo: ctx.repo)
        try prepareWorktree(ctx, at: wt, firstRef: list[0])

        var runs: [BranchRun] = []
        var skipped: [String] = []
        for (i, branch) in list.enumerated() {
            if Interrupt.isRequested { skipped = Array(list[i...]); break }
            Output.stderr("[\(i + 1)/\(list.count)] \(branch)")
            let ref = try resolveRef(branch, cwd: wt)
            try Shell.checked(["git", "checkout", "--detach", "--force", ref], cwd: wt)
            if Paths.exists(Paths.join(wt, ".gitmodules")) {
                try Shell.checked(["git", "submodule", "update", "--init", "--recursive"], cwd: wt)
            }
            if let prepare = ctx.config.prepare {
                let r = try Shell.run(["sh", "-c", prepare], cwd: wt)
                guard r.ok else { throw ProofError.commandFailed(prepare, r) }
            }
            var b = BuildOptions()
            b.action = "test"
            b.root = wt
            b.derivedData = Paths.worktreeDerivedData(repo: ctx.repo)
            b.onlyTesting = opts.onlyTesting
            b.verbose = opts.verbose
            // New warnings are counted against the branch below, like failures.
            let position = planned.branches.firstIndex(of: branch) ?? 0
            b.compareWarnings = position > 0 ? planned.branches[position - 1] : planned.base
            let (result, _) = try XcodeBuild.run(ctx.with(branch: branch, root: wt), b)
            runs.append(BranchRun(branch: branch, sha: (try? Git.shortSHA(cwd: wt)) ?? "?", result: result, pr: planned.prs[branch]))
            if opts.stopOnFail && !result.succeeded {
                skipped = Array(list[(i + 1)...])
                break
            }
        }
        let report = StackReport(branches: runs, introduced: StackReport.introducedMap(runs), skipped: skipped)
        try Paths.ensureDir(Paths.join(ctx.sessionDir, "results"))
        try Output.writeJSON(report, to: Paths.join(ctx.sessionDir, "results", "stack.json"))
        History.archive(report, kind: "stack", ok: report.ok, sessionDir: ctx.sessionDir)
        return report
    }

    static func prepareWorktree(_ ctx: Context, at wt: String, firstRef: String) throws {
        if Paths.exists(Paths.join(wt, ".git")) { return }
        try Paths.ensureDir((wt as NSString).deletingLastPathComponent)
        _ = try? Shell.run(["git", "worktree", "prune"], cwd: ctx.root)
        let ref = try resolveRef(firstRef, cwd: ctx.root)
        try Shell.checked(["git", "worktree", "add", "--detach", wt, ref], cwd: ctx.root)
    }

    /// Prefers the local branch (agents commit locally), falls back to origin/<branch>.
    static func resolveRef(_ branch: String, cwd: String) throws -> String {
        if (try? Shell.run(["git", "rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], cwd: cwd))?.ok == true { return branch }
        if (try? Shell.run(["git", "rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(branch)"], cwd: cwd))?.ok == true { return "origin/\(branch)" }
        throw ProofError.message("branch not found locally or on origin: \(branch)")
    }
}

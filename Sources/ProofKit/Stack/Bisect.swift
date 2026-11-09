import Foundation

/// `proof bisect`: the commit that broke a flow, changed a screen or made a test fail. A binary search over
/// the commits between a good and a bad one, each built and checked in the stack worktree, so neither your
/// checkout nor git's own bisect state changes. Commits that don't build are skipped.
public enum Bisect {
    public enum Check: Equatable {
        case flow(String)                    // bad when the flow fails
        case snap(flow: String, snap: String) // bad when the snap's tree differs from the good commit's
        case test(String)                    // bad when the test fails

        var description: String {
            switch self {
            case .flow(let f): return "flow \(f) breaks"
            case .snap(_, let s): return "screen \(s) changes"
            case .test(let t): return "test \(t) fails"
            }
        }
    }

    public enum Verdict: String, Codable { case good, bad, skip }

    /// Binary search for the first bad of `commits` commits, oldest to newest: the last is known bad, the
    /// parent of the first known good. `check` is asked about as few commits as possible; skipped commits make
    /// it try the nearest untried one. Returns the first bad index, or nil when skips leave it ambiguous.
    public static func search(_ commits: Int, check: (Int) throws -> Verdict) rethrows -> (first: Int?, candidates: Range<Int>) {
        var lo = -1, hi = commits - 1     // lo: last known good, hi: first known bad
        var skipped: Set<Int> = []
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            let order = (lo + 1..<hi).sorted { abs($0 - mid) < abs($1 - mid) }
            guard let next = order.first(where: { !skipped.contains($0) }) else { return (nil, lo + 1..<hi + 1) }
            switch try check(next) {
            case .good: lo = next
            case .bad: hi = next
            case .skip: skipped.insert(next)
            }
        }
        return (hi, hi..<hi + 1)
    }

    public struct Options {
        public var check: Check
        public var good: String? = nil
        public var bad: String? = nil
        public var verbose = false
        public init(check: Check) { self.check = check }
    }

    public static func run(_ ctx: Context, _ options: Options) throws -> BisectReport {
        let goodRef = try options.good ?? {
            let base = BaseBranch.resolve(BaseBranch.keyword, ctx: ctx) ?? ctx.trunk
            return try Shell.checked(["git", "merge-base", try StackRunner.resolveRef(base, cwd: ctx.root), "HEAD"], cwd: ctx.root)
        }()
        let badRef = options.bad ?? "HEAD"
        let good = try Shell.checked(["git", "rev-parse", "--verify", goodRef + "^{commit}"], cwd: ctx.root)
        let bad = try Shell.checked(["git", "rev-parse", "--verify", badRef + "^{commit}"], cwd: ctx.root)
        let commits = try Shell.checked(["git", "rev-list", "--reverse", "--ancestry-path", "\(good)..\(bad)"], cwd: ctx.root)
            .split(separator: "\n").map(String.init)
        guard !commits.isEmpty else { throw ProofError.message("\(badRef) is not after \(goodRef): nothing to search") }

        let wt = Paths.worktree(repo: ctx.repo)
        let derived = Paths.worktreeDerivedData(repo: ctx.repo)
        try StackRunner.prepareWorktree(ctx, at: wt, firstRef: good)
        var report = BisectReport(check: options.check.description, good: short(good), bad: short(bad))
        var reference: String?    // snap mode: the good commit's tree

        func evaluate(_ sha: String) throws -> Verdict {
            if Interrupt.isRequested { throw ProofError.message("bisect stopped") }
            Output.stderr("bisect: \(short(sha)) \(subject(sha, cwd: ctx.root))")
            let verdict = try check(sha, options: options, ctx: ctx, worktree: wt, derivedData: derived, reference: reference)
            report.steps.append(.init(sha: short(sha), subject: subject(sha, cwd: ctx.root), verdict: verdict.verdict))
            return verdict.verdict
        }

        // The ends first: the good commit gives the reference screen, the bad one must really be bad.
        if case .snap = options.check {
            let r = try check(good, options: options, ctx: ctx, worktree: wt, derivedData: derived, reference: nil)
            guard let tree = r.tree else { throw ProofError.message("the good commit \(short(good)) couldn't be snapped: \(r.reason ?? "?")") }
            reference = tree
            report.steps.append(.init(sha: short(good), subject: subject(good, cwd: ctx.root), verdict: .good))
        }
        guard try evaluate(bad) == .bad else {
            report.notes.append("\(short(bad)) isn't bad (no \(options.check.description) there), so there's nothing to find")
            return report
        }
        let found = try search(commits.count) { try evaluate(commits[$0]) }
        if let index = found.first {
            let sha = commits[index]
            report.culprit = .init(sha: short(sha), subject: subject(sha, cwd: ctx.root), verdict: .bad)
        } else {
            report.notes.append("some commits don't build, so it's one of: " + found.candidates.map { short(commits[$0]) }.joined(separator: ", "))
        }
        return report
    }

    struct Outcome { let verdict: Verdict; var tree: String? = nil; var reason: String? = nil }

    static func check(_ sha: String, options: Options, ctx: Context, worktree wt: String, derivedData derived: String,
                      reference: String?) throws -> Outcome {
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        switch options.check {
        case .test(let id):
            let session = ctx.with(branch: "bisect", root: wt)
            try Shell.checked(["git", "checkout", "--detach", "--force", sha], cwd: wt)
            var b = BuildOptions()
            b.action = "test"; b.root = wt; b.derivedData = derived; b.onlyTesting = [id]; b.verbose = options.verbose
            let (r, _) = try XcodeBuild.run(session, b)
            if !r.errors.isEmpty { return Outcome(verdict: .skip, reason: "build failed") }
            return Outcome(verdict: r.tests?.failed ?? 0 > 0 ? .bad : .good)
        case .flow(let name), .snap(let name, _):
            let prepared = try FlowStack.checkoutAndInstall(ctx, branch: "bisect", ref: sha, worktree: wt, derivedData: derived,
                                                            simulator: sim.udid, verbose: options.verbose)
            guard let product = prepared.product else { return Outcome(verdict: .skip, reason: "build failed") }
            var bctx = prepared.ctx
            if bctx.config.bundleId == nil { bctx.config.bundleId = product.bundleId }
            var o = FlowRunOptions()
            o.relaunch = true
            let flow = try Flow.load(name, repo: ctx.repo)
            let run = try FlowEngine.run(flow, ctx: bctx, options: o)
            if case .snap(_, let snapName) = options.check {
                guard let snap = Snaps.load(sessionDir: bctx.sessionDir).first(where: { $0.name == snapName }),
                      run.steps.contains(where: { $0.file == snap.screenshot }),
                      let tree = try? String(contentsOfFile: snap.tree, encoding: .utf8) else {
                    return Outcome(verdict: .skip, reason: "flow didn't reach snap \(snapName)")
                }
                guard let reference else { return Outcome(verdict: .good, tree: tree) }
                return Outcome(verdict: tree == reference ? .good : .bad, tree: tree)
            }
            return Outcome(verdict: run.ok ? .good : .bad)
        }
    }

    static func short(_ sha: String) -> String { String(sha.prefix(7)) }

    static func subject(_ sha: String, cwd: String) -> String {
        (try? Shell.checked(["git", "log", "-1", "--format=%s", sha], cwd: cwd)) ?? ""
    }
}

public struct BisectReport: Report, Codable {
    public struct Step: Codable, Equatable {
        public let sha: String
        public let subject: String
        public let verdict: Bisect.Verdict
    }

    public let check: String
    public let good: String
    public let bad: String
    public var culprit: Step? = nil
    public var steps: [Step] = []
    public var notes: [String] = []

    public var text: String {
        var out: [String]
        if let c = culprit {
            out = ["BISECT \(check) first in \(c.sha) \(c.subject) · \(steps.count) commit\(steps.count == 1 ? "" : "s") checked"]
        } else {
            out = ["BISECT \(check) · no single commit found (\(good)..\(bad))"]
        }
        out += steps.map { "  \($0.sha) \($0.verdict.rawValue.padding(toLength: 4, withPad: " ", startingAt: 0))  \($0.subject)" }
        out += notes
        return out.joined(separator: "\n")
    }
}

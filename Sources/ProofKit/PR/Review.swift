import Foundation

/// `proof review <PR>`: someone else's pull request, checked out in the stack worktree, built, its flows
/// replayed on the PR's base and on the PR, and the report opened with every screen before and after.
/// Your checkout is never touched; the simulator ends with the PR's app installed.
public enum Review {
    public struct PRInfo: Decodable, Equatable {
        public let number: Int
        public let title: String
        public let url: String
        public let headRefName: String
        public let baseRefName: String
        public let headRefOid: String
    }

    public struct Options {
        public var flows: [String]? = nil    // nil: every flow of the repo
        public var test = false
        public var freshBaseline = false
        public var verbose = false
        public init() {}
    }

    /// The session a reviewed PR's results go to: `pr-42`, so it never mixes with a local branch of the same name.
    public static func sessionBranch(_ number: Int) -> String { "pr-\(number)" }

    public static func fetchInfo(_ number: Int, cwd: String) throws -> PRInfo {
        let json = try Shell.checked(["gh", "pr", "view", String(number), "--json",
                                      "number,title,url,headRefName,baseRefName,headRefOid"], cwd: cwd)
        guard let info = try? JSONDecoder().decode(PRInfo.self, from: Data(json.utf8)) else {
            throw ProofError.message("could not read PR #\(number) from gh")
        }
        return info
    }

    public static func run(_ ctx: Context, number: Int, options: Options) throws -> ReviewReport {
        let info = try fetchInfo(number, cwd: ctx.root)
        // The PR's commits, also from a fork, and the latest base. Only remote-tracking data changes in your repo.
        try Shell.checked(["git", "fetch", "--quiet", "origin", "pull/\(number)/head", info.baseRefName], cwd: ctx.root)
        let baseSha = try Shell.checked(["git", "rev-parse", "origin/\(info.baseRefName)"], cwd: ctx.root)

        let flows = try (options.flows ?? Flow.list(repo: ctx.repo)).map { try Flow.load($0, repo: ctx.repo) }
        let wt = Paths.worktree(repo: ctx.repo)
        let derived = Paths.worktreeDerivedData(repo: ctx.repo)
        try StackRunner.prepareWorktree(ctx, at: wt, firstRef: info.baseRefName)
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        let head = sessionBranch(number)
        var report = ReviewReport(number: number, title: info.title, url: info.url, headBranch: info.headRefName,
                                  base: info.baseRefName, sha: String(info.headRefOid.prefix(7)))

        // 1. The base, for the flows whose snaps it doesn't have yet.
        let needBase = flows.filter {
            options.freshBaseline || !Baseline.missing($0, on: info.baseRefName, repo: ctx.repo).isEmpty
        }
        if !needBase.isEmpty {
            Output.stderr("review: \(info.baseRefName) first, for \(needBase.map(\.name).joined(separator: ", "))")
            let base = try FlowStack.checkoutAndInstall(ctx, branch: info.baseRefName, ref: baseSha, worktree: wt,
                                                        derivedData: derived, simulator: sim.udid, verbose: options.verbose)
            if let product = base.product {
                var bctx = base.ctx
                if bctx.config.bundleId == nil { bctx.config.bundleId = product.bundleId }
                var o = FlowRunOptions()
                o.relaunch = true
                for flow in needBase where !Interrupt.isRequested { _ = try FlowEngine.run(flow, ctx: bctx, options: o) }
            } else {
                report.notes.append("\(info.baseRefName) does not build, so screens are not compared")
            }
        }

        // 2. The PR: build (and test), replay every flow against the base.
        Output.stderr("review: #\(number) \(info.headRefName)")
        let pr = try FlowStack.checkoutAndInstall(ctx, branch: head, ref: info.headRefOid, worktree: wt,
                                                  derivedData: derived, simulator: sim.udid, verbose: options.verbose)
        var pctx = pr.ctx
        report.build = pr.build
        try Session.saveResult(pr.build, ctx: pctx)
        guard let product = pr.product else { return report }
        if pctx.config.bundleId == nil { pctx.config.bundleId = product.bundleId }

        if options.test && !Interrupt.isRequested {
            var b = BuildOptions()
            b.action = "test"; b.root = wt; b.derivedData = derived; b.verbose = options.verbose
            b.compareWarnings = info.baseRefName
            let (tests, _) = try XcodeBuild.run(pctx, b)
            report.tests = tests
            try Session.saveResult(tests, ctx: pctx)
            // Testing replaces the app on the simulator with a test host; put the PR's app back.
            try Shell.checked(["xcrun", "simctl", "install", sim.udid, product.path])
        }

        for flow in flows where !Interrupt.isRequested {
            var o = FlowRunOptions()
            o.relaunch = true
            o.compareWith = info.baseRefName
            let run = try FlowEngine.run(flow, ctx: pctx, options: o)
            var changed: [String: Int] = [:]
            for s in Snaps.load(sessionDir: pctx.sessionDir) where run.steps.contains(where: { $0.file == s.screenshot }) {
                changed[s.name] = s.diff?.count ?? 0
            }
            report.flows.append(.init(flow: run, changedScreens: changed))
        }

        _ = try Packet.build(pctx)
        report.packet = Paths.join(pctx.sessionDir, "report.html")
        return report
    }
}

public struct ReviewReport: Report, Codable {
    public struct FlowResult: Codable {
        public let flow: FlowRunReport
        public let changedScreens: [String: Int]   // snap name -> changed tree lines vs the base
    }

    public let number: Int
    public let title: String
    public let url: String
    public let headBranch: String
    public let base: String
    public let sha: String
    public var build: BriefResult? = nil
    public var tests: BriefResult? = nil
    public var flows: [FlowResult] = []
    public var packet: String? = nil
    public var notes: [String] = []

    public var ok: Bool {
        (build?.succeeded ?? false) && (tests?.succeeded ?? true) && flows.allSatisfy(\.flow.ok)
    }

    public var text: String {
        var out = ["REVIEW #\(number) \(title) · \(headBranch) → \(base) (\(sha))"]
        if let build { out.append(build.render(maxItems: 10)) }
        if let tests { out.append(tests.render(maxItems: 10)) }
        for f in flows {
            let okSteps = f.flow.steps.filter { $0.status == "ok" }.count
            var line = "\(f.flow.ok ? "✓" : "✗") flow \(f.flow.flow)  \(okSteps)/\(f.flow.steps.count) steps"
            if let at = f.flow.failedAt, let s = f.flow.steps.first(where: { $0.index == at }) {
                line += "  ✗ step \(at): \(s.line) — \(s.error ?? "failed")"
            }
            out.append(line)
            let changed = f.changedScreens.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            out.append(changed.isEmpty
                ? "    no screen changes vs \(base)"
                : "    screens changed vs \(base): " + changed.map { "\($0.key) (\($0.value) lines)" }.joined(separator: ", "))
        }
        if build?.succeeded == true && flows.isEmpty {
            out.append("no flows to replay: record one (`proof record start` … `proof record stop <name>`) to see screens")
        }
        out += notes
        if let packet { out.append("report → \((packet as NSString).abbreviatingWithTildeInPath)") }
        if build?.succeeded == true { out.append("the simulator now has #\(number)'s app; `proof run` puts yours back") }
        return out.joined(separator: "\n")
    }
}

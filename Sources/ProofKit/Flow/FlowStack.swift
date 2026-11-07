import Foundation

public struct BranchFlowRun: Codable {
    public let branch: String
    public let sha: String
    public let build: String                 // succeeded | failed | skipped
    public var buildErrors: [Diagnostic] = []
    public var flow: FlowRunReport?
    public var changedScreens: [String: Int] = [:]   // snap name -> changed tree lines vs comparison branch
    public var comparedWith: String?
    public var pr: Int? = nil                // open PR for the branch, when known
}

public struct StackFlowReport: Report, Codable {
    public let flow: String
    public let runs: [BranchFlowRun]
    public var ok: Bool { runs.allSatisfy { $0.build == "succeeded" && ($0.flow?.ok ?? false) } }

    public var text: String {
        var out = ["FLOW \(flow) on \(runs.count) branch\(runs.count == 1 ? "" : "es") · \(ok ? "all passed" : "failures")"]
        for r in runs {
            var line = "\(ok(r) ? "✓" : "✗") \(r.branch) (\(r.sha))"
            if r.build != "succeeded" {
                line += "  build \(r.build)"
                out.append(line)
                for e in r.buildErrors.prefix(3) { out.append("    error \(BriefResult.location(e.file, e.line, e.column))\(e.message)") }
                continue
            }
            if let f = r.flow {
                let okSteps = f.steps.filter { $0.status == "ok" }.count
                line += "  \(okSteps)/\(f.steps.count) steps"
                if let at = f.failedAt, let s = f.steps.first(where: { $0.index == at }) {
                    line += "  ✗ step \(at): \(s.line) — \(s.error ?? "failed")"
                }
            }
            out.append(line)
            let changed = r.changedScreens.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            if let base = r.comparedWith, !changed.isEmpty {
                out.append("    screens changed vs \(base): " + changed.map { "\($0.key) (\($0.value) lines)" }.joined(separator: ", "))
            }
        }
        return out.joined(separator: "\n")
    }

    private func ok(_ r: BranchFlowRun) -> Bool { r.build == "succeeded" && (r.flow?.ok ?? false) }
}

/// Replays a flow on every branch of the stack: checkout in the stack worktree, build, install,
/// relaunch, run. Each branch's snaps are compared with the branch below it (trunk for the first,
/// when trunk has snaps), so you see exactly which PR changed which screen.
public enum FlowStack {
    public static func run(_ ctx: Context, flowName: String, stack: StackOptions, options: FlowRunOptions) throws -> StackFlowReport {
        let flow = try Flow.load(flowName, repo: ctx.repo)
        let planned = try StackRunner.plan(ctx, explicit: stack.branches)
        var branches = planned.branches
        if let from = stack.from, let i = branches.firstIndex(of: from) { branches = Array(branches[i...]) }
        guard !branches.isEmpty else { throw ProofError.message("empty stack") }

        let wt = Paths.worktree(repo: ctx.repo)
        let derived = Paths.worktreeDerivedData(repo: ctx.repo)
        try StackRunner.prepareWorktree(ctx, at: wt, firstRef: branches[0])
        let sim = try Simulators.resolveBooted(ctx.config.simulator)

        var runs: [BranchFlowRun] = []
        // The first branch is compared with the branch its PR targets: the trunk, or a release branch.
        var previous: String? = planned.base
        for (i, branch) in branches.enumerated() {
            if Interrupt.isRequested { break }
            Output.stderr("[\(i + 1)/\(branches.count)] \(branch)")
            let ref = try StackRunner.resolveRef(branch, cwd: wt)
            try Shell.checked(["git", "checkout", "--detach", "--force", ref], cwd: wt)
            if Paths.exists(Paths.join(wt, ".gitmodules")) {
                try Shell.checked(["git", "submodule", "update", "--init", "--recursive"], cwd: wt)
            }
            if let prepare = ctx.config.prepare {
                let r = try Shell.run(["sh", "-c", prepare], cwd: wt)
                guard r.ok else { throw ProofError.commandFailed(prepare, r) }
            }
            let bctx = ctx.with(branch: branch, root: wt)
            let sha = (try? Git.shortSHA(cwd: wt)) ?? "?"

            var b = BuildOptions()
            b.root = wt
            b.derivedData = derived
            b.verbose = stack.verbose
            let (build, _) = try XcodeBuild.run(bctx, b)
            guard build.succeeded else {
                runs.append(BranchFlowRun(branch: branch, sha: sha, build: "failed", buildErrors: build.errors, pr: planned.prs[branch]))
                if stack.stopOnFail { break }
                previous = branch
                continue
            }
            let product = try XcodeBuild.appProduct(bctx, derivedData: derived)
            try Shell.checked(["xcrun", "simctl", "install", sim.udid, product.path])

            // Compare with the branch below only if it produced snaps (trunk usually has none until you snap it).
            let base = previous.flatMap { p in Snaps.load(sessionDir: Paths.session(repo: ctx.repo, branch: p)).isEmpty ? nil : p }
            var o = options
            o.relaunch = true
            o.compareWith = BaseBranch.resolve(options.compareWith, ctx: bctx) ?? base
            var bctxWithId = bctx
            if bctxWithId.config.bundleId == nil { bctxWithId.config.bundleId = product.bundleId }
            let report = try FlowEngine.run(flow, ctx: bctxWithId, options: o)

            var run = BranchFlowRun(branch: branch, sha: sha, build: "succeeded", flow: report, comparedWith: o.compareWith, pr: planned.prs[branch])
            for s in Snaps.load(sessionDir: bctx.sessionDir) where report.steps.contains(where: { $0.file == s.screenshot }) {
                run.changedScreens[s.name] = s.diff?.count ?? 0
            }
            runs.append(run)
            previous = branch
            if stack.stopOnFail && !report.ok { break }
        }
        let result = StackFlowReport(flow: flow.name, runs: runs)
        try Paths.ensureDir(Paths.join(ctx.sessionDir, "results"))
        try Output.writeJSON(result, to: Paths.join(ctx.sessionDir, "results", "flow-stack-\(Paths.sanitize(flow.name)).json"))
        History.archive(result, kind: "flow-stack", ok: result.ok, name: flow.name, sessionDir: ctx.sessionDir)
        return result
    }
}

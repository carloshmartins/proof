import Foundation

/// Before and after in one command. `proof flow run <flow> --compare <branch>` needs the flow's snaps on
/// `<branch>`. When some are missing, the flow is replayed there first: `<branch>` is checked out in the stack
/// worktree, built and installed, the flow runs, and then the current checkout is rebuilt and reinstalled
/// (uncommitted changes included) so the real run compares against fresh snaps.
public enum Baseline {
    /// The snap names a flow takes, in order, after includes. Names with `${VAR}` are resolved with `vars`.
    public static func snapNames(_ flow: Flow, vars: [String: String] = [:]) -> [String] {
        flow.steps.filter { $0.action == "snap" }.compactMap { $0.positional.first }.map { name in
            vars.reduce(name) { $0.replacingOccurrences(of: "${\($1.key)}", with: $1.value) }
        }
    }

    /// Snap names of `flow` that `branch` doesn't have yet.
    public static func missing(_ flow: Flow, on branch: String, repo: String, vars: [String: String] = [:]) -> [String] {
        let have = Set(Snaps.load(sessionDir: Paths.session(repo: repo, branch: branch)).map(\.name))
        return snapNames(flow, vars: vars).filter { !have.contains($0) }
    }

    /// Whether to replay the flow on `base` first.
    public static func isNeeded(_ flow: Flow, base: String, current: String, repo: String,
                                vars: [String: String] = [:], fresh: Bool) -> Bool {
        guard base != current, !snapNames(flow, vars: vars).isEmpty else { return false }
        return fresh || !missing(flow, on: base, repo: repo, vars: vars).isEmpty
    }

    /// Replays `flow` on `base` in the stack worktree, then reinstalls the current checkout's app.
    /// Returns a one-line summary. Never throws for a failing base: the comparison just has less to show.
    /// Fills in `ctx.config.bundleId` (and saves it, like `proof run`) when it wasn't known yet.
    @discardableResult
    public static func capture(_ ctx: inout Context, flow: Flow, base: String, options: FlowRunOptions, verbose: Bool) throws -> String {
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        let wt = Paths.worktree(repo: ctx.repo)
        try StackRunner.prepareWorktree(ctx, at: wt, firstRef: base)

        Output.stderr("baseline: replaying \(flow.name) on \(base) first, in \(Paths.display(wt))")
        let prepared = try FlowStack.checkoutAndInstall(ctx, branch: base, worktree: wt,
                                                        derivedData: Paths.worktreeDerivedData(repo: ctx.repo),
                                                        simulator: sim.udid, verbose: verbose)
        var summary: String
        if let product = prepared.product {
            var bctx = prepared.ctx
            if bctx.config.bundleId == nil { bctx.config.bundleId = product.bundleId }
            var o = options
            o.relaunch = true
            o.compareWith = nil
            o.video = false
            let report = try FlowEngine.run(flow, ctx: bctx, options: o)
            summary = "baseline: \(base) (\(prepared.sha)) · \(report.steps.filter { $0.status == "ok" }.count)/\(report.steps.count) steps ok"
            if let failed = report.failedAt { summary += " · failed at step \(failed), later snaps are missing" }
        } else {
            summary = "baseline: \(base) (\(prepared.sha)) · build failed (\(prepared.build.errors.count) error\(prepared.build.errors.count == 1 ? "" : "s")), comparing without it"
        }
        Output.stderr(summary)

        // Put the current checkout's app back on the simulator.
        Output.stderr("baseline: reinstalling \(ctx.branch)")
        let (build, _) = try XcodeBuild.run(ctx, BuildOptions())
        guard build.succeeded else {
            throw ProofError.message("\(ctx.branch) does not build:\n" + build.text)
        }
        let product = try XcodeBuild.appProduct(ctx)
        try Shell.checked(["xcrun", "simctl", "install", sim.udid, product.path])
        if ctx.config.bundleId == nil {
            ctx.config.bundleId = product.bundleId
            var store = ConfigStore.load()
            var c = store.repos[ctx.mainRoot] ?? ctx.config
            c.bundleId = product.bundleId
            store.repos[ctx.mainRoot] = c
            try store.save()
        }
        return summary
    }
}

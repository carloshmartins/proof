import Foundation

public struct StepResult: Codable, Equatable {
    public let index: Int            // 1-based
    public let line: String
    public var status: String        // ok | failed | skipped
    public var duration: Double = 0
    public var detail: String? = nil
    public var error: String? = nil
    public var file: String? = nil   // screenshot for snap steps
}

public struct FlowRunReport: Report, Codable {
    public let flow: String
    public let branch: String
    public let sha: String
    public var steps: [StepResult]
    public var failureSnap: String?
    public var video: String?
    public var duration: Double
    public var interrupted: Bool? = nil       // stopped by SIGINT (proof stop, Ctrl-C); remaining steps skipped
    public var crash: CrashReport? = nil      // the app crashed during the run

    public var ok: Bool { interrupted != true && steps.allSatisfy { $0.status == "ok" } }
    public var failedAt: Int? { steps.first(where: { $0.status == "failed" })?.index }

    public var text: String {
        let okCount = steps.filter { $0.status == "ok" }.count
        var head = "FLOW \(flow) · \(branch) (\(sha)) · \(okCount)/\(steps.count) ok"
        if let f = failedAt { head += " · FAILED at step \(f)" }
        if interrupted == true { head += " · INTERRUPTED" }
        head += String(format: " · %.1fs", duration)
        var out = [head]
        let width = min(48, steps.map(\.line.count).max() ?? 0)
        for s in steps {
            let mark = s.status == "ok" ? "✓" : s.status == "failed" ? "✗" : "-"
            let line = s.line.count > width ? String(s.line.prefix(width - 1)) + "…" : s.line.padding(toLength: width, withPad: " ", startingAt: 0)
            var row = "\(mark) \(String(format: "%2d", s.index)) \(line)"
            switch s.status {
            case "ok": row += String(format: "  %.1fs", s.duration)
            case "failed": row += "  \(s.error ?? "failed")"
            default: row += "  skipped"
            }
            out.append(row)
            if s.status == "ok", let d = s.detail, s.line.hasPrefix("snap"), d.contains("\n") {
                out.append(contentsOf: d.split(separator: "\n").dropFirst().prefix(12).map { "       " + $0 })
            }
        }
        if let crash { out.append(crash.text) }
        if let failureSnap { out.append("failure snap → \(failureSnap)") }
        if let video { out.append("video → \(video)") }
        return out.joined(separator: "\n")
    }
}

public struct FlowRunOptions {
    public var vars: [String: String] = [:]
    public var continueOnFailure = false
    public var compareWith: String? = nil     // default --compare for snap steps
    public var video = false
    public var relaunch = false               // launch the app first unless the flow starts with launch/attach
    public var variants: [SnapVariant] = []   // runVariants: replay once more per variant
    public var variant: SnapVariant? = nil    // this run's variant: look, launch arguments, snap names
    public init() {}
}

/// A flow replayed as is and once per variant (`proof flow run <flow> --variants dark,ar`).
public struct FlowVariantsReport: Report {
    public let runs: [FlowRunReport]
    public var ok: Bool { runs.allSatisfy(\.ok) }
    public var text: String { runs.map(\.text).joined(separator: "\n\n") }
}

public enum FlowEngine {
    public struct Outcome {
        public let detail: String
        public let file: String?
        public var target: StepTarget? = nil
        public init(detail: String, file: String?, target: StepTarget? = nil) { self.detail = detail; self.file = file; self.target = target }
    }

    /// Executes one step. Throws with an agent-readable message on failure.
    @discardableResult
    public static func perform(_ step: FlowStep, ctx: Context, compareWith: String? = nil) throws -> Outcome {
        switch step.action {
        case "snap":
            guard let name = step.positional.first else { throw ProofError.message("snap needs a name") }
            let compare = step.option("compare") ?? compareWith
            let variants = try SnapVariant.parseList(step.option("variants"))
            if let live = variants.first(where: \.needsRelaunch) {
                throw ProofError.message("snap --variants \(live.name): a locale or rtl needs a relaunch. "
                                         + "Put the snap in a flow and run `proof flow run <flow> --variants \(live.name)`")
            }
            let record = try Snaps.take(ctx, name: name, compareWith: compare)
            guard !variants.isEmpty else { return Outcome(detail: record.text, file: record.screenshot) }
            // The same screen in each look, then the simulator's own look back.
            let look = SimulatorLook(udid: try Simulators.resolveBooted(ctx.config.simulator).udid)
            defer { look.restore() }
            var texts = [record.text]
            for v in variants {
                try look.apply(v)
                texts.append(try Snaps.take(ctx, name: v.snapName(name), compareWith: compare).text)
            }
            return Outcome(detail: texts.joined(separator: "\n"), file: record.screenshot)
        case "sleep":
            let seconds = Double(step.positional.first ?? "1") ?? 1
            Thread.sleep(forTimeInterval: seconds)
            return Outcome(detail: "slept \(seconds)s", file: nil)
        case "include":
            throw ProofError.message("include is only valid inside a .flow file")
        case _ where FlowStep.simulatorActions.contains(step.action):
            return Outcome(detail: try SimState.perform(step, ctx: ctx), file: nil)
        case "wait", "expect":
            guard let (path, body) = try step.runnerRequest(defaultBundleId: ctx.config.bundleId) else { break }
            try Runner.ensureRunning(simulator: ctx.config.simulator)
            let timeout = body["timeout"] as? Double ?? 10
            let r = try Runner.request(path, body, timeout: timeout + 15)
            if r["ok"] as? Bool == true {
                return Outcome(detail: step.flag("gone") ? "gone" : "found", file: nil, target: step.flag("gone") ? nil : StepTarget.decode(r))
            }
            if let e = r["error"] as? String { throw ProofError.message(e) }
            let what = describeSelector(step)
            throw ProofError.message(step.flag("gone")
                ? "\(what) still present after \(Int(timeout))s"
                : "\(what) not found within \(Int(timeout))s. Run `proof ui tree`")
        default:
            break
        }
        guard let (path, body) = try step.runnerRequest(defaultBundleId: ctx.config.bundleId) else {
            throw ProofError.message("cannot execute step: \(step.line)")
        }
        let r = try Runner.command(path, body, simulator: ctx.config.simulator)
        let detail: String
        switch step.action {
        case "launch": detail = "launched \(r["bundleId"] as? String ?? "") (\(r["state"] as? String ?? "?"))"
        case "attach": detail = "attached \(r["bundleId"] as? String ?? "")"
        case "tap": detail = "tapped \(r["tapped"] as? String ?? "point")"
        case "longpress": detail = "pressed \(r["pressed"] as? String ?? "")"
        case "type": detail = "typed \(step.positional.first?.count ?? 0) chars"
        case "swipe": detail = "swiped \(body["direction"] as? String ?? "")"
        case "alert": detail = "alert \"\(r["alert"] as? String ?? "")\": tapped \(r["tapped"] as? String ?? "")"
        default: detail = step.action
        }
        return Outcome(detail: detail, file: nil, target: StepTarget.decode(r))
    }

    static func describeSelector(_ step: FlowStep) -> String {
        let parts = ["type", "id", "label", "text", "index"].compactMap { k in step.option(k).map { "\(k)=\($0)" } }
        return parts.isEmpty ? "element" : parts.joined(separator: " ")
    }

    /// Runs a flow, stopping at the first failure unless `continueOnFailure`. On failure it snaps
    /// the screen as "<flow>-failed" so the agent can see what was actually there.
    /// Replays the flow as is, then once per `options.variants`, each relaunched in its look. A device
    /// variant installs the app this checkout built on that simulator and moves the runner there.
    /// `product` is the app to install on other devices; by default the one this checkout built.
    public static func runVariants(_ flow: Flow, ctx: Context, options: FlowRunOptions,
                                   product built: XcodeBuild.AppProduct? = nil) throws -> FlowVariantsReport {
        var runs = [try run(flow, ctx: ctx, options: options)]
        var product = built
        for v in options.variants {
            if Interrupt.isRequested { break }
            var o = options
            o.variant = v
            o.relaunch = true
            o.video = false
            var vctx = ctx
            if let device = v.device {
                vctx.config.simulator = device
                let sim = try Simulators.resolveBooted(device)
                if product == nil { product = try XcodeBuild.appProduct(ctx) }
                try Shell.checked(["xcrun", "simctl", "install", sim.udid, product!.path])
                if vctx.config.bundleId == nil { vctx.config.bundleId = product!.bundleId }
            }
            runs.append(try run(flow, ctx: vctx, options: o))
        }
        return FlowVariantsReport(runs: runs)
    }

    /// A step as it runs under a variant: snaps get the variant's name, launches its launch arguments.
    static func adapt(_ step: FlowStep, to variant: SnapVariant?) -> FlowStep {
        guard let variant else { return step }
        var s = step
        if s.action == "snap", let name = s.positional.first {
            s.positional[0] = variant.snapName(name)
            s.options.removeAll { $0.name == "variants" }
        }
        if s.action == "launch" {
            s.options += variant.launchArguments.map { FlowStep.Option(name: "arg", value: $0) }
        }
        return s
    }

    public static func run(_ flow: Flow, ctx: Context, options: FlowRunOptions) throws -> FlowRunReport {
        var steps = flow.steps
        if options.relaunch, let first = steps.first?.action, first != "launch" && first != "attach" {
            steps.insert(FlowStep(action: "launch"), at: 0)
        } else if options.relaunch, steps.isEmpty {
            steps = [FlowStep(action: "launch")]
        }
        steps = steps.map { adapt($0, to: options.variant) }
        let look = try options.variant.map { _ in SimulatorLook(udid: try Simulators.resolveBooted(ctx.config.simulator).udid) }
        if let look, let v = options.variant { try look.apply(v) }
        defer { look?.restore() }
        let start = Date()
        var report = FlowRunReport(flow: options.variant.map { $0.snapName(flow.name) } ?? flow.name, branch: ctx.branch, sha: (try? Git.shortSHA(cwd: ctx.root)) ?? "?",
                                   steps: steps.enumerated().map { StepResult(index: $0 + 1, line: $1.line, status: "skipped") },
                                   failureSnap: nil, video: nil, duration: 0)
        Events.append(ProofEvent(kind: "flow", name: flow.name, status: "started", total: steps.count), ctx: ctx)

        if options.video {
            try Runner.ensureRunning(simulator: ctx.config.simulator)
            report.video = try? Video.start(ctx, name: flow.name)
        }

        var failed = false
        for (i, raw) in steps.enumerated() {
            if failed && !options.continueOnFailure { break }
            if Interrupt.isRequested { report.interrupted = true; break }
            let t0 = Date()
            var target: StepTarget?
            Events.append(ProofEvent(kind: "step", name: raw.line, status: "started", flow: flow.name, index: i + 1, total: steps.count), ctx: ctx)
            do {
                let step = try raw.substituting(options.vars)
                let outcome = try perform(step, ctx: ctx, compareWith: options.compareWith)
                report.steps[i].status = "ok"
                report.steps[i].detail = outcome.detail
                report.steps[i].file = outcome.file
                target = outcome.target
            } catch {
                report.steps[i].status = "failed"
                report.steps[i].error = "\(error)"
                failed = true
                if let crash = Crashes.unreported(ctx, since: start, wait: Crashes.looksLikeAppGone("\(error)") ? 5 : 0) {
                    report.crash = crash
                    report.steps[i].error = crash.summary
                }
            }
            report.steps[i].duration = Date().timeIntervalSince(t0)
            Events.append(ProofEvent(kind: "step", name: raw.line, status: report.steps[i].status,
                                     detail: report.steps[i].error ?? report.steps[i].detail, duration: report.steps[i].duration,
                                     file: report.steps[i].file, flow: flow.name, index: i + 1, total: steps.count,
                                     target: target), ctx: ctx)
        }

        if failed && report.interrupted != true {
            report.failureSnap = (try? Snaps.take(ctx, name: "\(flow.name)-failed", compareWith: nil))?.screenshot
        }
        if report.video != nil { report.video = Video.stop() ?? report.video }
        report.duration = Date().timeIntervalSince(start)

        let results = Paths.join(ctx.sessionDir, "results")
        try Paths.ensureDir(results)
        try Output.writeJSON(report, to: Paths.join(results, "flow-\(Paths.sanitize(flow.name)).json"))
        History.archive(report, kind: "flow", ok: report.ok, name: flow.name, sessionDir: ctx.sessionDir)
        Events.append(ProofEvent(kind: "flow", name: flow.name, status: report.ok ? "ok" : "failed",
                                 detail: report.interrupted == true ? "interrupted" : nil,
                                 duration: report.duration, file: report.video), ctx: ctx)
        return report
    }
}

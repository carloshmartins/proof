import ArgumentParser
import Foundation
import ProofKit

struct Record: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record `proof ui …` and `proof snap` commands into a flow.",
        discussion: """
        proof record start
        proof ui tap --id onboarding.skip      (each successful action is recorded)
        proof snap home
        proof record stop login                saves ~/.proof/flows/<repo>/login.flow
        """,
        subcommands: [Start.self, Stop.self, Status.self, Undo.self, Discard.self]
    )

    struct Start: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws {
            let ctx = try Context.current()
            if let s = Recorder.state() { throw ValidationError("already recording (\(s.lines.count) steps). `proof record stop <name>` or `proof record discard`") }
            try Recorder.start(ctx)
            Events.append(ProofEvent(kind: "record", name: "recording", status: "started"), ctx: ctx)
            try finish(MessageReport("recording · run proof ui commands, then `proof record stop <name>`"), g)
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop and save the recording as a flow.")
        @OptionGroup var g: Global
        @Argument(help: "Flow name.") var name: String
        @Flag(help: "Overwrite an existing flow.") var force = false
        func run() throws {
            guard let s = Recorder.state() else { throw ValidationError("no recording in progress") }
            guard !s.lines.isEmpty else { _ = Recorder.stop(); throw ValidationError("nothing was recorded") }
            let path = try Flow.save(name: name, lines: s.lines, repo: s.repo,
                                     header: ["recorded \(s.started) on \(s.branch)"], overwrite: force)
            _ = Recorder.stop()
            try finish(MessageReport("saved \(s.lines.count) steps → \(path)\nreplay: proof flow run \(name)"), g)
        }
    }

    struct Status: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws {
            guard let s = Recorder.state() else { try finish(MessageReport(ok: false, "not recording"), g); return }
            try finish(MessageReport((["recording \(s.lines.count) steps since \(s.started)"] + s.lines.enumerated().map { "\($0 + 1) \($1)" }).joined(separator: "\n")), g)
        }
    }

    struct Undo: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Drop the last recorded step(s).")
        @OptionGroup var g: Global
        @Argument var count: Int = 1
        func run() throws {
            let s = try Recorder.undo(count)
            try finish(MessageReport("\(s.lines.count) steps left" + (s.lines.last.map { " · last: \($0)" } ?? "")), g)
        }
    }

    struct Discard: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws { _ = Recorder.stop(); try finish(MessageReport("recording discarded"), g) }
    }
}

struct FlowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flow",
        abstract: "Replayable UI flows (~/.proof/flows/<repo>/<name>.flow).",
        discussion: """
        A flow is one `proof ui` step per line, without the prefix. Also: snap <name>, expect …,
        sleep <s>, include <flow>. Use ${NAME} for values from --var or the environment.

          launch --arg -resetState
          tap --id onboarding.skip
          type ${EMAIL} --id login.email
          tap --id login.submit
          expect --id home.title --timeout 15
          snap home
        """,
        subcommands: [RunFlow.self, List.self, Show.self, Check.self]
    )

    struct RunFlow: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "run", abstract: "Replay a flow on this branch, or on every branch of the stack with --stack.")
        @OptionGroup var g: Global
        @Argument(help: "Flow name or path to a .flow file.") var flow: String
        @Option(name: .customLong("var"), help: "NAME=value for ${NAME}. Repeatable.") var vars: [String] = []
        @Flag(name: .customLong("continue"), help: "Keep going after a failed step.") var continueOnFailure = false
        @Option(help: "Compare snaps with the same-named snaps of this branch, or \"base\" for the branch this PR targets.") var compare: String?
        @Flag(help: "Record a video of the run.") var video = false
        @Flag(help: "Relaunch the app first (default with --stack).") var relaunch = false
        @Flag(help: "Build, install and replay on every branch of the stack.") var stack = false
        @Option(help: "Explicit stack branches, bottom to top, comma separated.") var branches: String?
        @Option(help: "Start the stack run at this branch.") var from: String?
        @Flag(help: "Stop at the first failing branch.") var stopOnFail = false
        @Flag(help: "Stream raw xcodebuild output to stderr (stack builds).") var verbose = false
        @Flag(help: "With --compare: replay the flow on the compared branch first even if its snaps exist.") var freshBaseline = false
        @Flag(help: "With --compare: never replay the flow on the compared branch; compare with the snaps it has.") var noBaseline = false
        @Option(help: "Replay the flow again per variant, e.g. dark,ax5,ar,rtl (join with + to combine). Snaps are named <name>@<variant>.")
        var variants: String?

        func run() throws {
            var ctx = try Context.current()
            track(ctx)
            if freshBaseline && noBaseline { throw ValidationError("--fresh-baseline and --no-baseline can't be used together") }
            var o = FlowRunOptions()
            for v in vars {
                let p = v.split(separator: "=", maxSplits: 1).map(String.init)
                guard p.count == 2 else { throw ValidationError("--var expects NAME=value, got \(v)") }
                o.vars[p[0]] = p[1]
            }
            o.continueOnFailure = continueOnFailure
            o.compareWith = compare
            o.video = video
            o.relaunch = relaunch
            o.variants = try SnapVariant.parseList(variants)
            if stack && !o.variants.isEmpty { throw ValidationError("--variants doesn't work with --stack yet") }
            if stack {
                var s = StackOptions()
                s.branches = branches?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                s.from = from; s.stopOnFail = stopOnFail; s.verbose = verbose
                let report = try FlowStack.run(ctx, flowName: flow, stack: s, options: o)
                try finish(report, g, failed: !report.ok)
            } else {
                let loaded = try Flow.load(flow, repo: ctx.repo)
                // Before and after in one command: if the compared branch lacks this flow's snaps, take them there first.
                if let base = BaseBranch.resolve(compare, ctx: ctx), !noBaseline,
                   Baseline.isNeeded(loaded, base: base, current: ctx.branch, repo: ctx.repo, vars: o.vars,
                                     variants: o.variants, fresh: freshBaseline) {
                    try Baseline.capture(&ctx, flow: loaded, base: base, options: o, verbose: verbose)
                    o.compareWith = base
                    o.relaunch = true
                }
                if o.variants.isEmpty {
                    let report = try FlowEngine.run(loaded, ctx: ctx, options: o)
                    try finish(report, g, failed: !report.ok)
                } else {
                    let report = try FlowEngine.runVariants(loaded, ctx: ctx, options: o)
                    try finish(report, g, failed: !report.ok)
                }
            }
        }
    }

    struct List: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws {
            let ctx = try Context.current()
            let names = Flow.list(repo: ctx.repo)
            try finish(MessageReport(names.isEmpty ? "no flows yet · record one: proof record start" : names.joined(separator: "\n")), g)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print a flow with includes expanded.")
        @OptionGroup var g: Global
        @Argument var flow: String
        func run() throws {
            let ctx = try Context.current()
            let f = try Flow.load(flow, repo: ctx.repo)
            try finish(MessageReport((["# \(f.path)"] + f.steps.enumerated().map { "\($0 + 1) \($1.line)" }).joined(separator: "\n")), g)
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Validate a flow without running it (syntax, includes, variables).")
        @OptionGroup var g: Global
        @Argument var flow: String
        @Option(name: .customLong("var"), help: "NAME=value. Repeatable.") var vars: [String] = []
        func run() throws {
            let ctx = try Context.current()
            let f = try Flow.load(flow, repo: ctx.repo)
            var v: [String: String] = [:]
            for pair in vars { let p = pair.split(separator: "=", maxSplits: 1).map(String.init); if p.count == 2 { v[p[0]] = p[1] } }
            var problems: [String] = []
            for s in f.steps {
                do {
                    let step = try s.substituting(v)
                    let bundle = ctx.config.bundleId ?? "check.bundle"
                    if FlowStep.simulatorActions.contains(step.action) { _ = try SimState.command(for: step, udid: "check", bundleId: bundle) }
                    else if step.action == "snap" { _ = try SnapVariant.parseList(step.option("variants")) }
                    else { _ = try step.runnerRequest(defaultBundleId: bundle) }
                }
                catch {
                    let msg = "\(error)"
                    problems.append(msg.hasPrefix("line ") ? msg : "line \(s.sourceLine ?? 0): \(msg)")
                }
            }
            try finish(MessageReport(ok: problems.isEmpty, problems.isEmpty ? "flow \(f.name) ok · \(f.steps.count) steps" : problems.joined(separator: "\n")),
                       g, failed: !problems.isEmpty)
        }
    }
}

struct VideoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "video", abstract: "Record the simulator screen.", subcommands: [Start.self, Stop.self])

    struct Start: ParsableCommand {
        @OptionGroup var g: Global
        @Argument var name: String = "session"
        func run() throws {
            let ctx = try Context.current()
            let path = try Video.start(ctx, name: name)
            try finish(MessageReport("recording video → \(path)\nstop: proof video stop"), g)
        }
    }

    struct Stop: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws {
            guard let path = Video.stop() else { throw ValidationError("no video recording") }
            if let ctx = try? Context.current() { Events.append(ProofEvent(kind: "video", name: "video", status: "ok", file: path), ctx: ctx) }
            try finish(MessageReport("video → \(path)"), g)
        }
    }
}

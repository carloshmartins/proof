import ArgumentParser
import Foundation
import ProofKit

struct Selector: ParsableArguments {
    @Option(help: "Exact accessibility identifier.") var id: String?
    @Option(help: "Exact accessibility label.") var label: String?
    @Option(help: "Case-insensitive substring of label or identifier.") var text: String?
    @Option(help: "Element type: button, textfield, cell, switch, …") var type: String?
    @Option(help: "Index among matches (0-based).") var index: Int?

    var tokens: [String] {
        var t: [String] = []
        if let type { t += ["--type", type] }
        if let id { t += ["--id", id] }
        if let label { t += ["--label", label] }
        if let text { t += ["--text", text] }
        if let index { t += ["--index", String(index)] }
        return t
    }
}

/// Runs one step exactly like a flow would, logs it, and appends it to an active recording.
func performStep(_ tokens: [String], _ g: Global) throws {
    let (_, outcome) = try executeStep(tokens)
    try finish(MessageReport(outcome.detail), g)
}

@discardableResult
func executeStep(_ tokens: [String]) throws -> (FlowStep, FlowEngine.Outcome) {
    let ctx = try Context.current()
    let step = try FlowStep.parse(tokens: tokens)
    let t0 = Date()
    Events.append(ProofEvent(kind: "step", name: step.line, status: "started"), ctx: ctx)
    let outcome: FlowEngine.Outcome
    do {
        outcome = try FlowEngine.perform(step, ctx: ctx)
    } catch {
        Events.append(ProofEvent(kind: "step", name: step.line, status: "failed", detail: "\(error)",
                                 duration: Date().timeIntervalSince(t0)), ctx: ctx)
        throw error
    }
    Events.append(ProofEvent(kind: "step", name: step.line, status: "ok", detail: outcome.detail,
                             duration: Date().timeIntervalSince(t0), file: outcome.file, target: outcome.target), ctx: ctx)
    Recorder.record(step, repo: ctx.repo)
    return (step, outcome)
}

func runnerCommand(_ path: String, _ body: [String: Any]) throws -> [String: Any] {
    let ctx = try? Context.current()
    return try Runner.command(path, body, simulator: ctx?.config.simulator)
}

func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

struct UI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Drive the iOS Simulator through the accessibility tree (no UI test target needed).",
        discussion: "Every action command is also a flow step: while `proof record` is on, it is recorded.",
        subcommands: [Start.self, Stop.self, Status.self, Launch.self, Attach.self, Terminate.self, Tree.self, At.self,
                      Tap.self, LongPress.self, TypeText.self, Swipe.self, Wait.self, Expect.self, Home.self, Alert.self,
                      Open.self, Push.self, Permission.self, Location.self]
    )

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build (once) and start the runner on the configured simulator.")
        @OptionGroup var g: Global
        @Flag(help: "Rebuild the runner even if it looks current.") var rebuild = false
        func run() throws {
            let ctx = try? Context.current()
            if rebuild { Runner.stop(); try Runner.buildIfNeeded(force: true) }
            let s = try Runner.ensureRunning(simulator: ctx?.config.simulator)
            try finish(MessageReport("runner on 127.0.0.1:\(s.port) · simulator \(s.udid)"), g)
        }
    }

    struct Stop: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws { Runner.stop(); try finish(MessageReport("runner stopped"), g) }
    }

    struct Status: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws {
            let healthy = Runner.isHealthy()
            let s = Runner.state()
            var lines = [healthy ? "runner running · port \(s?.port ?? Runner.port) · \(s?.udid ?? "?")" : "runner stopped"]
            if let r = Recorder.state() { lines.append("recording \(r.lines.count) step\(r.lines.count == 1 ? "" : "s") since \(r.started)") }
            if Video.isRecording { lines.append("video recording") }
            try finish(MessageReport(ok: healthy, lines.joined(separator: "\n")), g)
        }
    }

    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch (or relaunch) the app under test.")
        @OptionGroup var g: Global
        @Option(help: "Bundle id; defaults to the configured one.") var bundleId: String?
        @Option(name: .customLong("arg"), parsing: .unconditionalSingleValue, help: "Launch argument. Repeatable.") var args: [String] = []
        @Option(name: .customLong("env"), parsing: .unconditionalSingleValue, help: "KEY=VALUE launch environment. Repeatable.") var env: [String] = []
        func run() throws {
            var t = ["launch"]
            if let bundleId { t += ["--bundle-id", bundleId] }
            for a in args { t += ["--arg", a] }
            for e in env { t += ["--env", e] }
            try performStep(t, g)
        }
    }

    struct Attach: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Attach to the already-running app without relaunching.")
        @OptionGroup var g: Global
        @Option(help: "Bundle id; defaults to the configured one.") var bundleId: String?
        func run() throws { try performStep(["attach"] + (bundleId.map { ["--bundle-id", $0] } ?? []), g) }
    }

    struct Terminate: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws { try performStep(["terminate"], g) }
    }

    struct Tree: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the accessibility tree of the current screen.")
        @OptionGroup var g: Global
        @Flag(help: "Include element frames.") var frames = false
        @Flag(name: .shortAndLong, help: "Only interactive elements, flat.") var interactive = false
        @Flag(help: "Only interactive elements missing an accessibility identifier.") var missingIds = false

        struct TreeReport: Report {
            let nodes: [UINode]
            let screen: ScreenSize?
            let rendered: String
            var text: String { rendered }
            enum CodingKeys: String, CodingKey { case nodes, screen }
        }

        func run() throws {
            let response = try runnerCommand("/tree", [:])
            var nodes = try UITree.decode(response)
            let screen = UITree.screen(response).map { ScreenSize(width: $0[0], height: $0[1]) }
            if missingIds { nodes = UITree.missingIdentifiers(nodes) }
            let rendered = missingIds
                ? (nodes.isEmpty ? "all interactive elements have identifiers" : UITree.render(nodes, frames: frames, interactiveOnly: true))
                : UITree.render(nodes, frames: frames, interactiveOnly: interactive)
            try finish(TreeReport(nodes: nodes, screen: screen, rendered: rendered), g)
        }
    }

    struct At: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Which element is at a point (in points)? Prints it and the flow step that targets it.",
            discussion: """
            With --tap it also taps it through that selector (and records it). This is click-to-record.
            --as expect records an expect for the element instead, --as snap:<name> snaps the screen.
            """)
        @OptionGroup var g: Global
        @Argument var x: Double
        @Argument var y: Double
        @Flag(help: "Tap the element via its selector.") var tap = false
        @Option(name: .customLong("as"), help: "Perform and record the step as tap, expect or snap:<name>.") var asAction: String?

        struct AtReport: Report {
            let element: UINode?
            let selector: [String]
            let step: String
            var detail: String? = nil
            var performed = false
            var text: String {
                let head = (element.map { $0.line().trimmingCharacters(in: .whitespaces) } ?? "no element") + "\nstep: " + step
                return detail.map { head + "\n" + $0 } ?? head
            }
        }

        func run() throws {
            let nodes = try UITree.decode(try runnerCommand("/tree", [:]))
            let hit = UITree.hitTest(nodes, x: x, y: y)
            let point = ["--x", fmt(x), "--y", fmt(y)]
            let found = hit.map { UITree.selectorTokens(for: $0, in: nodes) } ?? []
            let selector = found.isEmpty ? point : found
            let action = asAction ?? "tap"
            let tokens = try AtStep.tokens(as: action, selector: selector)
            let element = hit.map { nodes[$0] }
            if tap || asAction != nil {
                let (step, outcome) = try executeStep(tokens)
                try finish(AtReport(element: element, selector: selector, step: step.line, detail: outcome.detail, performed: true), g)
            } else {
                try finish(AtReport(element: element, selector: selector, step: try FlowStep.parse(tokens: tokens).line), g)
            }
        }
    }

    struct Tap: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Tap an element (or --x/--y in points).")
        @OptionGroup var g: Global
        @OptionGroup var sel: Selector
        @Option var x: Double?
        @Option var y: Double?
        func run() throws {
            var t = ["tap"] + sel.tokens
            if let x, let y { t += ["--x", fmt(x), "--y", fmt(y)] }
            try performStep(t, g)
        }
    }

    struct LongPress: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "longpress")
        @OptionGroup var g: Global
        @OptionGroup var sel: Selector
        @Option(help: "Seconds.") var duration: Double?
        func run() throws { try performStep(["longpress"] + sel.tokens + (duration.map { ["--duration", String($0)] } ?? []), g) }
    }

    struct TypeText: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "type", abstract: "Type text, optionally into a selected field.")
        @OptionGroup var g: Global
        @Argument var text: String
        @OptionGroup var sel: Selector
        @Flag(help: "Clear the field first.") var clear = false
        @Flag(help: "Press return afterwards.") var submit = false
        func run() throws {
            try performStep(["type", text] + sel.tokens + (clear ? ["--clear"] : []) + (submit ? ["--submit"] : []), g)
        }
    }

    struct Swipe: ParsableCommand {
        @OptionGroup var g: Global
        @Argument(help: "up | down | left | right") var direction: String
        @OptionGroup var sel: Selector
        func run() throws { try performStep(["swipe", direction] + sel.tokens, g) }
    }

    struct Wait: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Wait for an element to appear (or disappear with --gone). Default 10s.")
        @OptionGroup var g: Global
        @OptionGroup var sel: Selector
        @Option var timeout: Double?
        @Flag var gone = false
        func run() throws {
            try performStep(["wait"] + sel.tokens + (timeout.map { ["--timeout", String($0)] } ?? []) + (gone ? ["--gone"] : []), g)
        }
    }

    struct Expect: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Assert an element is on screen (or gone with --gone). Default 5s. Use as a flow checkpoint.")
        @OptionGroup var g: Global
        @OptionGroup var sel: Selector
        @Option var timeout: Double?
        @Flag var gone = false
        func run() throws {
            try performStep(["expect"] + sel.tokens + (timeout.map { ["--timeout", String($0)] } ?? []) + (gone ? ["--gone"] : []), g)
        }
    }

    struct Home: ParsableCommand {
        @OptionGroup var g: Global
        func run() throws { try performStep(["home"], g) }
    }

    struct Alert: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Handle an in-app or system alert (accepts by default).")
        @OptionGroup var g: Global
        @Option(help: "Exact button label to tap.") var button: String?
        @Flag(help: "Tap the first (cancel) button instead of the last.") var dismiss = false
        func run() throws { try performStep(["alert"] + (button.map { ["--button", $0] } ?? []) + (dismiss ? ["--dismiss"] : []), g) }
    }

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a URL on the simulator: a deep link or universal link.")
        @OptionGroup var g: Global
        @Argument(help: "The URL, e.g. tempo://presets/new.") var url: String
        func run() throws { try performStep(["open", url], g) }
    }

    struct Push: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Send a push notification to the app under test.",
            discussion: "Build it from --title, --body, --badge and --sound, or pass a full APNs payload with --payload.")
        @OptionGroup var g: Global
        @Option var title: String?
        @Option var body: String?
        @Option var badge: Int?
        @Option var sound: String?
        @Option(help: "JSON file with an \"aps\" key; other keys reach the app as custom data.") var payload: String?
        @Option(help: "Bundle id; defaults to the configured one.") var bundleId: String?
        func run() throws {
            var t = ["push"]
            if let title { t += ["--title", title] }
            if let body { t += ["--body", body] }
            if let badge { t += ["--badge", String(badge)] }
            if let sound { t += ["--sound", sound] }
            if let payload { t += ["--payload", payload] }
            if let bundleId { t += ["--bundle-id", bundleId] }
            try performStep(t, g)
        }
    }

    struct Permission: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Grant, revoke or reset a privacy permission for the app under test.",
            discussion: "Services: \(SimState.services.joined(separator: ", ")). Revoking may terminate the app.")
        @OptionGroup var g: Global
        @Argument(help: "grant | revoke | reset") var verb: String
        @Argument(help: "The service, e.g. photos, location, contacts, microphone.") var service: String
        @Option(help: "Bundle id; defaults to the configured one.") var bundleId: String?
        func run() throws { try performStep(["permission", verb, service] + (bundleId.map { ["--bundle-id", $0] } ?? []), g) }
    }

    struct Location: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set the simulated location (latitude,longitude), or clear it.")
        @OptionGroup var g: Global
        @Argument(help: "latitude,longitude, e.g. 51.5072,-0.1276") var coordinate: String?
        @Flag(help: "Stop simulating a location.") var clear = false
        func run() throws {
            guard clear || coordinate != nil else { throw ValidationError("give latitude,longitude or --clear") }
            try performStep(clear ? ["location", "--clear"] : ["location", coordinate!], g)
        }
    }
}


// MARK: - ax

struct AX: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find interactive controls without accessibility identifiers.",
        subcommands: [Scan.self, Audit.self]
    )

    struct Scan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Static scan of Swift, xib and storyboard files.")
        @OptionGroup var g: Global
        @Argument(help: "Files or folders. Defaults to the repo root.") var paths: [String] = []
        @Option(name: .customLong("control"), help: "Custom control type to check, e.g. PrimaryButton. Repeatable.") var controls: [String] = []
        @Flag(help: "Also scan test targets.") var includeTests = false
        @Flag(help: "Exit non-zero when anything is missing.") var strict = false

        func run() throws {
            let ctx = try Context.current()
            let targets = paths.isEmpty ? [ctx.root] : paths.map { $0.hasPrefix("/") ? $0 : Paths.join(FileManager.default.currentDirectoryPath, $0) }
            let report = AXScanner(extraControls: controls, includeTests: includeTests).scan(paths: targets, root: ctx.root)
            try Paths.ensureDir(Paths.join(ctx.sessionDir, "results"))
            try Output.writeJSON(report, to: Paths.join(ctx.sessionDir, "results", "ax.json"))
            History.archive(report, kind: "ax", ok: report.findings.isEmpty, sessionDir: ctx.sessionDir)
            try finish(report, g, failed: strict && !report.findings.isEmpty)
        }
    }

    struct Audit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Runtime audit of the current screen via the runner.")
        @OptionGroup var g: Global
        func run() throws {
            let nodes = UITree.missingIdentifiers(try UITree.decode(try runnerCommand("/tree", [:])))
            let text = nodes.isEmpty ? "AX AUDIT clean" : "AX AUDIT \(nodes.count) without identifier\n" + UITree.render(nodes, interactiveOnly: true)
            try finish(MessageReport(ok: nodes.isEmpty, text), g)
        }
    }
}

// MARK: - pr

struct PR: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "GitHub PR helpers.", subcommands: [Comments.self])

    struct Comments: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unresolved review threads, reviews and comments, condensed for agents.")
        @OptionGroup var g: Global
        @Argument(help: "PR number. Defaults to the current branch's PR.") var number: Int?
        @Flag(help: "Include resolved threads.") var all = false
        @Flag(help: "Exclude bot authors.") var noBots = false
        @Flag(help: "Do not truncate long bodies.") var full = false

        func run() throws {
            let root = try Git.root()
            var o = PRComments.Options()
            o.includeResolved = all; o.includeBots = !noBots; o.maxBody = full ? 0 : 600
            let json = try PRComments.fetch(number: number, cwd: root)
            try finish(try PRComments.report(fromJSON: json, options: o), g)
        }
    }
}

import ArgumentParser
import Foundation
import ProofKit

@main
struct Proof: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proof",
        abstract: "Make agents prove their iOS changes work: build, test the stack, drive the simulator, snap, packet.",
        discussion: """
        Typical loop:
          proof build                 condensed build result
          proof test --stack          every branch of the stack, regressions marked
          proof run                   build, install, launch on the simulator
          proof ui tree               what is on screen (accessibility tree)
          proof ui tap --id login     interact
          proof snap login --compare base
          proof record start / stop login     turn what you did into a flow
          proof flow run login --stack        replay it on every branch
          proof packet --open         review screenshots and diffs, not the diff

        Everything is stored under ~/.proof. Nothing is written to your repo.
        """,
        version: "0.2.0",
        subcommands: [
            Init.self, Setup.self, Doctor.self, Build.self, Brief.self, Test.self, Run.self, Stop.self,
            UI.self, Snap.self, Record.self, FlowCommand.self, VideoCommand.self, AX.self, PR.self, ReviewCommand.self, PacketCommand.self,
        ]
    )
}

struct Global: ParsableArguments {
    @Flag(name: .long, help: "Machine-readable JSON output for agents.")
    var json = false
}

/// Emits a report and exits non-zero when it represents a failure.
func finish<R: Report>(_ report: R, _ g: Global, failed: Bool = false) throws {
    Output.emit(report, json: g.json)
    if failed { throw ExitCode(1) }
}

/// Registers a long-running command in ~/.proof/active so viewers can show it and `proof stop` can end it.
func track(_ ctx: Context) {
    ActiveRuns.begin(command: Array(CommandLine.arguments.dropFirst()), ctx: ctx)
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop the newest running proof command (build, test, run, flow run) cleanly, as Ctrl-C would.",
        discussion: "Results so far are still written. Nothing running is not an error.")
    @OptionGroup var g: Global
    @Flag(help: "Stop every running proof command.") var all = false

    func run() throws {
        try finish(StopReport(stopped: ActiveRuns.stop(all: all)), g)
    }
}

// MARK: - setup / init / doctor

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install the runner sources and the agent skill that ship with this proof binary.",
        discussion: """
        Copies the runner sources to ~/.proof/runner/src and SKILL.md to the skill folder.
        Looks for them next to the binary: Contents/Resources in an app bundle that ships proof, or the repo in a checkout.
        Safe to run again.
        """)
    @OptionGroup var g: Global
    @Option(help: "Skills folder your agent reads (default ~/.claude/skills/proof).") var skillDir: String?
    @Option(name: .customLong("agent"), help: "Install the skill for this agent: claude, codex, cursor, copilot or all. Repeatable.")
    var agents: [String] = []

    func run() throws {
        guard let resources = Installer.resources(executable: Bundle.main.executablePath ?? CommandLine.arguments[0]) else {
            throw ProofError.message("runner sources and skill not found next to this binary. Run it from a proof checkout (make install)")
        }
        var dirs = try Installer.skillDirs(agents: agents)
        if let skillDir { dirs.append((skillDir as NSString).expandingTildeInPath) }
        if dirs.isEmpty { dirs = [Installer.defaultSkillDir] }
        try finish(try Installer.install(resources, skillDirs: dirs), g)
    }
}

// MARK: - init / doctor

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Save settings for this repo (stored in ~/.proof/config.json).")
    @OptionGroup var g: Global
    @Option(help: "Scheme to build and test.") var scheme: String?
    @Option(help: "Workspace path relative to the repo root.") var workspace: String?
    @Option(help: "Project path relative to the repo root.") var project: String?
    @Option(help: "Test plan name.") var testPlan: String?
    @Option(help: "Simulator name or UDID, e.g. \"iPhone 16\".") var simulator: String?
    @Option(help: "Bundle identifier of the app under test.") var bundleId: String?
    @Option(help: "Branch your stacks start from (default: the repo's default branch, e.g. main or develop).") var trunk: String?
    @Option(help: "Shell command to run in a checkout before building, e.g. \"tuist generate\".") var prepare: String?
    @Flag(help: "Print the current config only.") var show = false
    @Flag(help: "Remove this repo from proof (keeps its sessions and flows).") var forget = false

    func run() throws {
        let ctx = try Context.current()
        var store = ConfigStore.load()
        if forget {
            store.repos[ctx.mainRoot] = nil
            try store.save()
            try finish(MessageReport("forgot \(ctx.repo) (\(ctx.mainRoot))"), g)
            return
        }
        var c = store.repos[ctx.mainRoot] ?? RepoConfig()
        if !show {
            if let workspace { c.workspace = workspace; c.project = nil }
            if let project { c.project = project; c.workspace = nil }
            if c.workspace == nil && c.project == nil { autodetectContainer(ctx.mainRoot, &c) }
            if let scheme { c.scheme = scheme }
            if let testPlan { c.testPlan = testPlan }
            if let simulator { c.simulator = simulator }
            if let bundleId { c.bundleId = bundleId }
            if let trunk { c.trunk = trunk }
            if let prepare { c.prepare = prepare }
            store.repos[ctx.mainRoot] = c
            try store.save()
        }
        let lines = [
            "repo       \(ctx.repo)  (\(ctx.mainRoot))",
            "container  \(c.workspace ?? c.project ?? "auto")",
            "scheme     \(c.scheme ?? "— set with --scheme")",
            "test plan  \(c.testPlan ?? "scheme default")",
            "simulator  \(c.simulator ?? "first booted")",
            "bundle id  \(c.bundleId ?? "detected on first `proof run`")",
            "trunk      \(c.trunk ?? "\(ctx.defaultBranch ?? "main") (repo default)")",
        ] + (c.prepare.map { ["prepare    \($0)"] } ?? [])
        try finish(MessageReport(lines.joined(separator: "\n")), g)
    }

    func autodetectContainer(_ root: String, _ c: inout RepoConfig) {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        if let w = items.first(where: { $0.hasSuffix(".xcworkspace") }) { c.workspace = w }
        else if let p = items.first(where: { $0.hasSuffix(".xcodeproj") }) { c.project = p }
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check tools, config and runner.")
    @OptionGroup var g: Global

    func run() throws {
        var lines: [String] = []
        var ok = true
        func check(_ name: String, _ pass: Bool, _ hint: String) {
            lines.append("\(pass ? "✓" : "✗") \(name)\(pass ? "" : "  → \(hint)")")
            if !pass { ok = false }
        }
        check("xcodebuild", Shell.which("xcodebuild") != nil, "install Xcode and run xcode-select")
        check("git", Shell.which("git") != nil, "install git")
        check("gh", Shell.which("gh") != nil, "brew install gh (needed for stacks and PR comments)")
        check("runner sources", Paths.exists(Paths.join(Paths.runnerSource, "ProofRunner.xcodeproj")), "run `proof setup`")
        if let ctx = try? Context.current() {
            check("scheme configured", ctx.config.scheme != nil, "proof init --scheme <Scheme>")
            if let scheme = ctx.config.scheme, let ok = XcodeBuild.supportsSimulator(ctx, scheme: scheme) {
                check("scheme runs on iOS Simulator", ok, "\(scheme) has no iOS Simulator destination (a macOS scheme?). proof init --scheme <iOS scheme>")
            }
            if let sims = try? Simulators.list() {
                check("simulator", Simulators.pick(ctx.config.simulator, from: sims) != nil || ctx.config.simulator == nil,
                      "proof init --simulator \"<name>\"")
            }
        }
        lines.append("runner \(Runner.isHealthy() ? "running" : "stopped")")
        try finish(MessageReport(ok: ok, lines.joined(separator: "\n")), g, failed: !ok)
    }
}

// MARK: - build / brief / test / run

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build the scheme for the simulator and print a condensed result.")
    @OptionGroup var g: Global
    @Flag(help: "List warnings, not just the count.") var warnings = false
    @Flag(help: "Stream raw xcodebuild output to stderr.") var verbose = false
    @Option(help: "Count new warnings against this branch, or \"base\" for the branch this PR targets. \"none\" turns it off.")
    var compare = BaseBranch.keyword
    @Argument(parsing: .postTerminator, help: "Extra xcodebuild arguments after --.") var extra: [String] = []

    func run() throws {
        let ctx = try Context.current()
        track(ctx)
        var o = BuildOptions()
        o.action = "build"; o.keepWarnings = warnings; o.verbose = verbose; o.extra = extra
        o.compareWarnings = warningsBase(compare, ctx)
        let (result, _) = try XcodeBuild.run(ctx, o)
        try Session.saveResult(result, ctx: ctx)
        try finish(result, g, failed: !result.succeeded)
    }
}

/// The branch to count new warnings against: nil for "none", for this branch, or when no other branch of
/// the repo has saved warnings yet (then `base` isn't resolved, which would ask GitHub).
func warningsBase(_ value: String, _ ctx: Context) -> String? {
    guard value != "none" else { return nil }
    let sessions = Paths.join(Paths.home, "sessions", ctx.repo)
    let others = ((try? FileManager.default.contentsOfDirectory(atPath: sessions)) ?? []).filter { $0 != Paths.sanitize(ctx.branch) }
    guard others.contains(where: { Warnings.load(sessionDir: Paths.join(sessions, $0)) != nil }) else { return nil }
    guard let base = BaseBranch.resolve(value, ctx: ctx), base != ctx.branch else { return nil }
    return base
}

struct Brief: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Condense xcodebuild output from stdin: xcodebuild … 2>&1 | proof brief")
    @OptionGroup var g: Global
    @Flag(help: "List warnings, not just the count.") var warnings = false

    func run() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let root = try? Git.root()
        let result = BriefParser(root: root, keepWarnings: warnings).parse(String(decoding: data, as: UTF8.self))
        try finish(result, g, failed: result.status == "failed")
    }
}

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run tests on this branch, or on every branch of the stack with --stack.")
    @OptionGroup var g: Global
    @Flag(help: "Test every branch of the current stack in a dedicated worktree.") var stack = false
    @Option(name: .customLong("only"), help: "Only run this test identifier (Target/Class/test). Repeatable.") var only: [String] = []
    @Option(name: .customLong("skip"), help: "Skip this test identifier. Repeatable.") var skip: [String] = []
    @Option(help: "Explicit stack branches, bottom to top, comma separated.") var branches: String?
    @Option(help: "Start the stack run at this branch.") var from: String?
    @Flag(help: "Stop the stack run at the first failing branch.") var stopOnFail = false
    @Option(help: "Run a failing test up to N times in all. One that passes on a retry is reported as flaky, not failed.")
    var retry: Int?
    @Flag(help: "Report which of the lines this branch changed the tests run (against --compare, default the PR's base).")
    var coverage = false
    @Option(help: "Count new warnings against this branch, or \"base\" for the branch this PR targets. \"none\" turns it off. With --stack, each branch is compared with the one below it.")
    var compare = BaseBranch.keyword
    @Flag(help: "Stream raw xcodebuild output to stderr.") var verbose = false

    func run() throws {
        let ctx = try Context.current()
        track(ctx)
        if stack {
            var o = StackOptions()
            o.branches = branches?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            o.from = from; o.stopOnFail = stopOnFail; o.onlyTesting = only; o.verbose = verbose; o.retry = retry
            let report = try StackRunner.run(ctx, o)
            try finish(report, g, failed: !report.ok)
        } else {
            var o = BuildOptions()
            o.action = "test"; o.onlyTesting = only; o.skipTesting = skip; o.verbose = verbose; o.retry = retry
            if coverage { o.coverageBase = BaseBranch.resolve(compare == "none" ? BaseBranch.keyword : compare, ctx: ctx) }
            o.compareWarnings = warningsBase(compare, ctx)
            let (result, _) = try XcodeBuild.run(ctx, o)
            try Session.saveResult(result, ctx: ctx)
            try finish(result, g, failed: !result.succeeded)
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build, install and launch the app on the simulator, attached to the runner.")
    @OptionGroup var g: Global
    @Option(name: .customLong("arg"), parsing: .unconditionalSingleValue, help: "Launch argument. Repeatable.") var args: [String] = []
    @Flag(help: "Skip the build, just reinstall and relaunch.") var noBuild = false

    func run() throws {
        var ctx = try Context.current()
        track(ctx)
        if !noBuild {
            let (result, _) = try XcodeBuild.run(ctx, BuildOptions())
            try Session.saveResult(result, ctx: ctx)
            guard result.succeeded else { try finish(result, g, failed: true); return }
        }
        let product = try XcodeBuild.appProduct(ctx)
        if ctx.config.bundleId == nil {
            var store = ConfigStore.load()
            var c = store.repos[ctx.mainRoot] ?? ctx.config
            c.bundleId = product.bundleId
            store.repos[ctx.mainRoot] = c
            try store.save()
            ctx.config.bundleId = product.bundleId
        }
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        try Shell.checked(["xcrun", "simctl", "install", sim.udid, product.path])
        try performStep(["launch"] + args.flatMap { ["--arg", $0] }, g)
    }
}

// MARK: - snap / packet

struct Snap: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Screenshot + accessibility tree of the current screen, saved for the packet.")
    @OptionGroup var g: Global
    @Argument(help: "Screen name, e.g. login or settings-empty.") var name: String
    @Option(help: "Diff the tree against the same-named snap of a branch: a name like main or develop, or \"base\" for the branch this PR targets.") var compare: String?

    @Option(help: "Also snap the screen in these looks, e.g. dark,ax5,dark+ax3 (appearance and text size). Snaps are named <name>@<variant>; the simulator's look is put back after.")
    var variants: String?

    func run() throws {
        try performStep(["snap", name] + (compare.map { ["--compare", $0] } ?? []) + (variants.map { ["--variants", $0] } ?? []), g)
    }
}

struct PacketCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "packet", abstract: "Bundle this branch's build, tests, stack, ax scan and snaps into report.md / report.html.")
    @OptionGroup var g: Global
    @Flag(help: "Open report.html in the browser.") var open = false
    @Flag(help: "Print the full markdown, not just the summary.") var print = false
    @Flag(help: "Delete this branch's session (snaps, results, logs).") var reset = false

    func run() throws {
        let ctx = try Context.current()
        if reset {
            try Packet.reset(ctx)
            try finish(MessageReport("cleared \(ctx.sessionDir)"), g)
            return
        }
        let report = try Packet.build(ctx)
        if open { _ = try? Shell.run(["open", Paths.join(ctx.sessionDir, "report.html")]) }
        if g.json || print { Output.emit(report, json: g.json) } else { Swift.print(report.summary) }
    }
}

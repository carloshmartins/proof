import Foundation

public struct BuildOptions {
    public var action = "build"                 // "build" | "test"
    public var root: String? = nil              // override checkout (stack worktree)
    public var derivedData: String? = nil
    public var onlyTesting: [String] = []
    public var skipTesting: [String] = []
    public var extra: [String] = []
    public var verbose = false                  // stream raw output to stderr
    public var keepWarnings = false
    public init() {}
}

public enum XcodeBuild {
    /// Runs xcodebuild for the configured scheme and returns the condensed result.
    /// The raw log is kept in the session folder so nothing is lost. While it runs, a progress line on
    /// stderr says what xcodebuild is doing (unless `verbose` streams the raw output instead).
    public static func run(_ ctx: Context, _ opts: BuildOptions) throws -> (BriefResult, logPath: String) {
        let scheme = try ctx.requireScheme()
        let root = opts.root ?? ctx.root
        var args = ["xcodebuild", opts.action]
        args += ctx.containerArgs(root: root)
        args += ["-scheme", scheme]
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        args += ["-destination", Simulators.destination(sim)]
        if let dd = opts.derivedData { args += ["-derivedDataPath", dd] }
        if opts.action == "test" {
            if let plan = ctx.config.testPlan { args += ["-testPlan", plan] }
            args += opts.onlyTesting.map { "-only-testing:\($0)" }
            args += opts.skipTesting.map { "-skip-testing:\($0)" }
        }
        args += ctx.config.extraBuildArgs ?? []
        args += opts.extra

        let start = Date()
        let label = opts.root == nil ? scheme : "\(scheme) @ \(Paths.relative(root, to: Paths.home))"
        Events.append(ProofEvent(kind: opts.action, name: label, status: "started"), ctx: ctx)

        // The raw log is written as xcodebuild runs, so `tail -f` on it shows a long build live.
        let logs = Paths.join(ctx.sessionDir, "logs")
        try Paths.ensureDir(logs)
        let logPath = Paths.join(logs, "\(opts.action)-\(Session.timestamp()).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: logPath)
        defer { try? log?.close() }

        let verb = opts.action == "test" ? "testing" : "building"
        let progress = opts.verbose ? nil
            : ProgressLine("\(verb) \(label) on \(sim.name)", detail: "log: \((logPath as NSString).abbreviatingWithTildeInPath)")
        let r = try Shell.run(args, cwd: root, tee: opts.verbose ? FileHandle.standardError : nil) { chunk in
            log?.write(chunk)
            progress?.feed(chunk)
        }
        progress?.finish()
        let duration = Date().timeIntervalSince(start)

        var brief = BriefParser(root: root, keepWarnings: opts.keepWarnings).parse(r.combined, action: opts.action, duration: duration)
        if brief.status == "unknown" { brief.status = r.ok ? "succeeded" : "failed" }
        Events.append(ProofEvent(kind: opts.action, name: label, status: brief.succeeded ? "ok" : "failed",
                                 detail: brief.text.split(separator: "\n").first.map(String.init), duration: duration, file: logPath), ctx: ctx)
        return (brief, logPath)
    }

    public struct AppProduct { public let path: String; public let bundleId: String }

    /// Finds the built .app for the scheme via -showBuildSettings.
    public static func appProduct(_ ctx: Context, derivedData: String? = nil) throws -> AppProduct {
        let scheme = try ctx.requireScheme()
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        var args = ["xcodebuild", "-showBuildSettings", "-json"] + ctx.containerArgs() + ["-scheme", scheme, "-destination", Simulators.destination(sim)]
        if let derivedData { args += ["-derivedDataPath", derivedData] }
        let r = try Shell.run(args, cwd: ctx.root)
        guard r.ok else {
            // A scheme that can't target the simulator: say which platforms it does build for, like `proof build`.
            if r.combined.contains("Unable to find a destination matching") {
                throw ProofError.message(BriefParser.destinationError(args.joined(separator: " ") + "\n" + r.combined))
            }
            throw ProofError.commandFailed(args.joined(separator: " "), r)
        }
        let json = r.stdout
        guard let product = parseAppProduct(fromBuildSettingsJSON: json, scheme: scheme) else {
            let others = otherPlatformApps(fromBuildSettingsJSON: json)
            if others.isEmpty { throw ProofError.message("no .app product found for scheme \(scheme)") }
            throw ProofError.message("scheme \(scheme) builds no iOS app (it builds \(others.joined(separator: ", "))). "
                                     + "Pick the scheme of the iOS app: proof init --scheme <name>")
        }
        return product
    }

    /// Whether the scheme can run on the iOS Simulator, from `xcodebuild -showdestinations`.
    /// Nil when xcodebuild fails (for example the workspace is not generated yet).
    public static func supportsSimulator(_ ctx: Context, scheme: String) -> Bool? {
        let args = ["xcodebuild", "-showdestinations"] + ctx.containerArgs() + ["-scheme", scheme]
        guard let r = try? Shell.run(args, cwd: ctx.root), r.ok else { return nil }
        return listsSimulator(showDestinations: r.stdout)
    }

    /// Only the "Available destinations" block counts; "Ineligible destinations" may list simulators too.
    public static func listsSimulator(showDestinations output: String) -> Bool {
        var available = false
        for line in output.split(separator: "\n") {
            if line.contains("Available destinations") { available = true; continue }
            if line.contains("Ineligible destinations") { available = false; continue }
            if available, line.contains("platform:iOS Simulator") { return true }
        }
        return false
    }

    struct SettingsEntry: Decodable { let target: String?; let buildSettings: [String: String] }

    static func appEntries(_ json: String) -> [SettingsEntry] {
        let entries = (try? JSONDecoder().decode([SettingsEntry].self, from: Data(json.utf8))) ?? []
        return entries.filter { $0.buildSettings["WRAPPER_EXTENSION"] == "app" }
    }

    /// The app to install on the simulator. A scheme can build several apps (a workspace scheme builds the
    /// macOS app, example apps and the iOS app): only apps built for the iOS Simulator count, the one named
    /// like the scheme first, examples and demos last. Apps without PLATFORM_NAME are kept as a fallback.
    public static func parseAppProduct(fromBuildSettingsJSON json: String, scheme: String? = nil) -> AppProduct? {
        func rank(_ e: SettingsEntry) -> Int {
            let target = (e.target ?? e.buildSettings["TARGET_NAME"] ?? "").lowercased()
            var r = e.buildSettings["PLATFORM_NAME"] == "iphonesimulator" ? 0 : 10
            if let scheme, target != scheme.lowercased() { r += 1 }
            if ["example", "demo", "sample", "playground"].contains(where: target.contains) { r += 2 }
            return r
        }
        let candidates = appEntries(json).filter { e in
            let platform = e.buildSettings["PLATFORM_NAME"]
            return platform == nil || platform == "iphonesimulator"
        }
        for e in candidates.enumerated().sorted(by: { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }).map(\.element) {
            let s = e.buildSettings
            guard let dir = s["TARGET_BUILD_DIR"], let name = s["WRAPPER_NAME"], let id = s["PRODUCT_BUNDLE_IDENTIFIER"] else { continue }
            return AppProduct(path: Paths.join(dir, name), bundleId: id)
        }
        return nil
    }

    /// "Nub (macosx)" for each app the scheme builds for a platform other than the iOS Simulator.
    public static func otherPlatformApps(fromBuildSettingsJSON json: String) -> [String] {
        appEntries(json).compactMap { e in
            guard let p = e.buildSettings["PLATFORM_NAME"], p != "iphonesimulator" else { return nil }
            return "\(e.target ?? e.buildSettings["WRAPPER_NAME"] ?? "app") (\(p))"
        }
    }
}

public enum Session {
    public static func timestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Latest build/test result per action, read by `proof packet`.
    public static func saveResult(_ result: BriefResult, ctx: Context) throws {
        let dir = Paths.join(ctx.sessionDir, "results")
        try Paths.ensureDir(dir)
        try Output.writeJSON(result, to: Paths.join(dir, "\(result.action).json"))
        History.archive(result, kind: result.action, ok: result.succeeded, sessionDir: ctx.sessionDir)
    }

    public static func loadResult(_ action: String, sessionDir: String) -> BriefResult? {
        Output.readJSON(BriefResult.self, from: Paths.join(sessionDir, "results", "\(action).json"))
    }
}

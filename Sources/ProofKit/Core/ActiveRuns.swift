import Foundation

/// A long-running proof command, registered in ~/.proof/active/<pid>.json while it runs so viewers can
/// show it and `proof stop` can end it.
public struct ActiveRun: Codable, Equatable {
    public let pid: Int32
    public let command: String       // arguments after `proof`, e.g. "flow run login --video"
    public let repo: String
    public let branch: String
    public let started: Date

    public init(pid: Int32, command: String, repo: String, branch: String, started: Date = Date()) {
        self.pid = pid; self.command = command; self.repo = repo; self.branch = branch; self.started = started
    }
}

public enum ActiveRuns {
    public static var dir: String { Paths.join(Paths.home, "active") }
    static func file(_ pid: Int32) -> String { Paths.join(dir, "\(pid).json") }

    /// Registers this process. The file is removed at exit (atexit), including after `proof stop`,
    /// because SIGINT is turned into a clean stop by `Interrupt`.
    public static func begin(command: [String], ctx: Context) {
        Interrupt.install()
        let run = ActiveRun(pid: getpid(), command: command.joined(separator: " "), repo: ctx.repo, branch: ctx.branch)
        try? Paths.ensureDir(dir)
        try? Output.writeJSON(run, to: file(run.pid))
        registerCleanup()
    }

    public static func end() { try? FileManager.default.removeItem(atPath: file(getpid())) }

    private static var cleanupRegistered = false
    private static func registerCleanup() {
        guard !cleanupRegistered else { return }
        cleanupRegistered = true
        atexit { ActiveRuns.end() }
    }

    /// Runs still alive, newest first. Files left behind by crashed processes are removed.
    public static func list(isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }) -> [ActiveRun] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var runs: [ActiveRun] = []
        for name in names where name.hasSuffix(".json") {
            let path = Paths.join(dir, name)
            guard let run = Output.readJSON(ActiveRun.self, from: path) else { continue }
            if isAlive(run.pid) { runs.append(run) } else { try? FileManager.default.removeItem(atPath: path) }
        }
        return runs.sorted { $0.started > $1.started }
    }

    /// Sends SIGINT to the newest run, or to all. Returns the runs signalled.
    public static func stop(all: Bool, isAlive: (Int32) -> Bool = { kill($0, 0) == 0 },
                            signal send: (Int32) -> Void = { _ = kill($0, SIGINT) }) -> [ActiveRun] {
        let runs = list(isAlive: isAlive)
        let targets = all ? runs : Array(runs.prefix(1))
        targets.forEach { send($0.pid) }
        return targets
    }
}

/// Turns SIGINT (Ctrl-C, `proof stop`, a viewer's Stop) into a clean stop: child processes get SIGINT,
/// loops check `isRequested` and write their results. A second SIGINT exits at once.
public enum Interrupt {
    private static let lock = NSLock()
    private static var requested = false
    private static var children = Set<Int32>()
    private static var source: DispatchSourceSignal?

    public static var isRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return requested
    }

    public static func install() {
        lock.lock(); defer { lock.unlock() }
        guard source == nil else { return }
        // A no-op handler, not SIG_IGN: ignored signals are inherited by exec'd children (xcodebuild would
        // then ignore our forwarded SIGINT), caught ones are reset to default. The dispatch source still fires.
        signal(SIGINT) { _ in }
        let s = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        s.setEventHandler { Interrupt.handle() }
        s.resume()
        source = s
    }

    /// Marks the stop request and forwards it to running children. Internal so tests can call it.
    static func handle() {
        lock.lock()
        let second = requested
        requested = true
        let pids = children
        lock.unlock()
        if second {
            pids.forEach { kill($0, SIGTERM) }
            Output.stderr("interrupted")
            exit(130)
        }
        Output.stderr("stopping… (Ctrl-C again to quit now)")
        pids.forEach { kill($0, SIGINT) }
    }

    static func track(_ pid: Int32) {
        lock.lock()
        children.insert(pid)
        let forward = requested
        lock.unlock()
        if forward { kill(pid, SIGINT) }
    }

    static func untrack(_ pid: Int32) {
        lock.lock(); children.remove(pid); lock.unlock()
    }

    /// For tests.
    static func reset() {
        lock.lock(); requested = false; children.removeAll(); lock.unlock()
    }
}

public struct StopReport: Report {
    public let stopped: [ActiveRun]
    public init(stopped: [ActiveRun]) { self.stopped = stopped }
    public var text: String {
        guard !stopped.isEmpty else { return "nothing running" }
        return stopped.map { "stopped proof \($0.command) · \($0.repo) \($0.branch) (pid \($0.pid))" }.joined(separator: "\n")
    }
}

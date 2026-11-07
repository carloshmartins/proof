import Foundation

/// Everything proof writes lives under ~/.proof — never inside your repos.
///
///   ~/.proof/config.json                     per-repo settings, keyed by repo root
///   ~/.proof/runner/                         runner sources + DerivedData (built once)
///   ~/.proof/worktrees/<repo>/               reusable worktree for stack test runs
///   ~/.proof/sessions/<repo>/<branch>/       snaps, results, packet.md
public enum Paths {
    public static var home: String {
        ProcessInfo.processInfo.environment["PROOF_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".proof")
    }

    public static var configFile: String { join(home, "config.json") }
    public static var runnerDir: String { join(home, "runner") }
    public static var runnerSource: String { join(runnerDir, "src") }
    public static var runnerDerivedData: String { join(runnerDir, "DerivedData") }
    public static var runnerState: String { join(runnerDir, "state.json") }
    public static var runnerLog: String { join(runnerDir, "runner.log") }

    public static func worktree(repo: String) -> String { join(home, "worktrees", repo) }
    public static func worktreeDerivedData(repo: String) -> String { join(home, "worktrees", repo + "-DerivedData") }
    public static func session(repo: String, branch: String) -> String {
        join(home, "sessions", repo, sanitize(branch))
    }

    public static func join(_ parts: String...) -> String {
        parts.dropFirst().reduce(parts[0]) { ($0 as NSString).appendingPathComponent($1) }
    }

    public static func ensureDir(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// Branch names contain "/" — flatten them for directory names.
    /// A path for messages: the home folder shown as `~`.
    public static func display(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    public static func sanitize(_ s: String) -> String {
        String(s.map { $0 == "/" || $0 == ":" || $0 == " " ? "_" : $0 })
    }

    /// Resolves symlinks with realpath(3), so paths compare equal to what git reports
    /// (on macOS /var and /tmp live under /private). Returns the path unchanged if it doesn't exist.
    public static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Makes an absolute path relative to `base` when it lives inside it. Saves tokens in agent output.
    public static func relative(_ path: String, to base: String?) -> String {
        guard let base, !base.isEmpty else { return path }
        let b = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(b) ? String(path.dropFirst(b.count)) : path
    }
}

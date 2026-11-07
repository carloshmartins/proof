import Foundation

/// Per-repo settings, stored in ~/.proof/config.json keyed by the main checkout path.
/// Linked worktrees resolve to the same entry, so every agent worktree shares it.
public struct RepoConfig: Codable, Equatable {
    public var workspace: String?      // relative to repo root, e.g. App.xcworkspace
    public var project: String?        // relative to repo root, e.g. App.xcodeproj
    public var scheme: String?
    public var testPlan: String?
    public var simulator: String?      // simulator name ("iPhone 16") or UDID
    public var bundleId: String?       // app under test, for `proof ui launch`
    public var trunk: String?          // base branch of stacks, default "main"
    public var extraBuildArgs: [String]?
    public var prepare: String?        // shell command run in a checkout before building (e.g. "tuist generate")

    public init() {}

    public var trunkBranch: String { trunk ?? "main" }
}

public struct ConfigStore: Codable {
    public var repos: [String: RepoConfig] = [:]

    public static func load() -> ConfigStore {
        guard let data = FileManager.default.contents(atPath: Paths.configFile),
              let store = try? JSONDecoder().decode(ConfigStore.self, from: data) else { return ConfigStore() }
        return store
    }

    public func save() throws {
        try Paths.ensureDir(Paths.home)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: Paths.configFile))
    }
}

/// Everything a command needs to know about where it is running.
public struct Context {
    public let root: String          // current checkout root (may be a linked worktree)
    public let mainRoot: String      // main checkout root (config key)
    public let repo: String          // repo name
    public let branch: String
    public var config: RepoConfig

    public static func current(cwd: String? = nil) throws -> Context {
        let root = try Git.root(cwd: cwd)
        let main = (try? Git.mainRoot(cwd: root)) ?? root
        let repo = (try? Git.repoName(cwd: root)) ?? (root as NSString).lastPathComponent
        let branch = (try? Git.currentBranch(cwd: root)) ?? "detached"
        let config = ConfigStore.load().repos[main] ?? RepoConfig()
        return Context(root: root, mainRoot: main, repo: repo, branch: branch, config: config)
    }

    public var sessionDir: String { Paths.session(repo: repo, branch: branch) }

    /// Same repo and config, different checkout/branch (stack worktree runs).
    public func with(branch: String, root: String) -> Context {
        Context(root: root, mainRoot: mainRoot, repo: repo, branch: branch, config: config)
    }

    /// xcodebuild container arguments (-workspace / -project), resolved against `root`.
    public func containerArgs(root overrideRoot: String? = nil) -> [String] {
        let base = overrideRoot ?? root
        if let w = config.workspace { return ["-workspace", Paths.join(base, w)] }
        if let p = config.project { return ["-project", Paths.join(base, p)] }
        return []
    }

    public func requireScheme() throws -> String {
        guard let s = config.scheme else {
            throw ProofError.message("no scheme configured. Run: proof init --scheme <Scheme>")
        }
        return s
    }
}

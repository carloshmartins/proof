import Foundation

/// Which branch a change is measured against. proof never assumes `main`:
///
/// - **trunk**: the branch your stacks start from. `proof init --trunk <branch>` sets it; otherwise it's the
///   repository's default branch on GitHub (`origin/HEAD`), then a local `main`, `master` or `develop`.
/// - **base**: the branch a pull request targets. `--compare base` compares with it, so each PR in a stack is
///   compared with the PR below it, and a PR into `release/2.0` is compared with `release/2.0`.
public enum BaseBranch {
    /// The `--compare` value that means "the branch this PR targets".
    public static let keyword = "base"

    /// Local branch names tried, in order, when the remote has no default branch.
    static let conventional = ["main", "master", "develop", "trunk"]

    /// `origin/develop` or `refs/remotes/origin/develop` → `develop`.
    public static func fromRemoteHead(_ ref: String) -> String? {
        var s = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("refs/remotes/") { s.removeFirst("refs/remotes/".count) }
        guard let slash = s.firstIndex(of: "/") else { return nil }
        let name = String(s[s.index(after: slash)...])
        return name.isEmpty || name == "HEAD" ? nil : name
    }

    /// The repository's default branch from what git knows locally.
    public static func pick(remoteHead: String?, localBranches: [String]) -> String? {
        if let remoteHead, let name = fromRemoteHead(remoteHead) { return name }
        return conventional.first { localBranches.contains($0) }
    }

    /// The branch an open PR for `branch` targets, if there is one.
    public static func prBase(of branch: String, pulls: [PullRef]) -> String? {
        pulls.first { $0.headRefName == branch }?.baseRefName
    }

    /// Resolves a `--compare` value: `base` becomes the PR's base branch (or the trunk without a PR);
    /// any other value is a branch name and is returned as is.
    public static func resolve(_ value: String?, branch: String, trunk: String, pulls: () -> [PullRef]) -> String? {
        guard let value else { return nil }
        guard value == keyword else { return value }
        return prBase(of: branch, pulls: pulls()) ?? trunk
    }

    /// `resolve` for a checkout, asking GitHub for open PRs only when `base` is used (once per process).
    public static func resolve(_ value: String?, ctx: Context) -> String? {
        resolve(value, branch: ctx.branch, trunk: ctx.trunk) { cachedPulls(cwd: ctx.mainRoot) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var pullsCache: [String: [PullRef]] = [:]

    static func cachedPulls(cwd: String) -> [PullRef] {
        lock.lock(); defer { lock.unlock() }
        if let cached = pullsCache[cwd] { return cached }
        let pulls = (try? StackResolver.fetchPulls(cwd: cwd)) ?? []
        pullsCache[cwd] = pulls
        return pulls
    }
}

extension Git {
    /// The repository's default branch: `origin/HEAD`, else a conventional local branch. Nil if neither exists.
    public static func defaultBranch(cwd: String? = nil) -> String? {
        let head = try? Shell.run(["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], cwd: cwd)
        let remoteHead = head.flatMap { $0.ok ? $0.stdout : nil }
        let local = (try? Shell.run(["git", "for-each-ref", "--format=%(refname:short)", "refs/heads/"], cwd: cwd))
            .map { $0.stdout.split(separator: "\n").map(String.init) } ?? []
        return BaseBranch.pick(remoteHead: remoteHead, localBranches: local)
    }
}

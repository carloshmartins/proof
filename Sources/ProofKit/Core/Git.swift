import Foundation

public enum Git {
    public static func root(cwd: String? = nil) throws -> String {
        do { return try Shell.checked(["git", "rev-parse", "--show-toplevel"], cwd: cwd) }
        catch { throw ProofError.message("not inside a git repository") }
    }

    public static func currentBranch(cwd: String? = nil) throws -> String {
        // symbolic-ref also works in a repo without commits; fall back to the SHA when detached.
        if let r = try? Shell.run(["git", "symbolic-ref", "--short", "-q", "HEAD"], cwd: cwd), r.ok {
            let b = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty { return b }
        }
        return try shortSHA(cwd: cwd)
    }

    public static func shortSHA(_ ref: String = "HEAD", cwd: String? = nil) throws -> String {
        try Shell.checked(["git", "rev-parse", "--short", ref], cwd: cwd)
    }

    public static func isClean(cwd: String? = nil) throws -> Bool {
        try Shell.checked(["git", "status", "--porcelain"], cwd: cwd).isEmpty
    }

    /// Repo name used for ~/.proof subfolders. For a linked worktree, use the main repo's name,
    /// so all your agent worktrees share one config entry.
    public static func repoName(cwd: String? = nil) throws -> String {
        let common = try Shell.checked(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: cwd)
        // common is <main-repo>/.git
        let main = (common as NSString).deletingLastPathComponent
        return (main as NSString).lastPathComponent
    }

    /// Root of the main checkout (not the linked worktree), for config lookup.
    public static func mainRoot(cwd: String? = nil) throws -> String {
        let common = try Shell.checked(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: cwd)
        return (common as NSString).deletingLastPathComponent
    }
}

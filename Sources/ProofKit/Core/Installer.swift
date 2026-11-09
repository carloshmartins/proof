import Foundation

/// Installs what the proof binary needs beside it: the runner sources (built on first `proof ui` use)
/// and the agent skill. Used by `proof setup`, `make install` and apps that bundle proof.
public enum Installer {
    /// A folder holding `Runner/ProofRunner.xcodeproj` and `skill/proof/SKILL.md`.
    public struct Resources: Equatable {
        public let root: String
        public var runner: String { Paths.join(root, "Runner") }
        public var skill: String { Paths.join(root, "skill", "proof", "SKILL.md") }

        public init(root: String) { self.root = root }

        public var isComplete: Bool {
            Paths.exists(Paths.join(runner, "ProofRunner.xcodeproj")) && Paths.exists(skill)
        }
    }

    /// Where the agent skill goes unless `--skill-dir` or `--agent` says otherwise.
    public static var defaultSkillDir: String {
        Paths.join(NSHomeDirectory(), ".claude", "skills", "proof")
    }

    /// Each agent's personal skills folder (they all read the same SKILL.md format). Personal, not per repo,
    /// so nothing is written to your repositories.
    public static let agentSkillDirs: [(agent: String, dir: String)] = [
        ("claude", ".claude/skills/proof"),     // Claude Code
        ("codex", ".agents/skills/proof"),      // OpenAI Codex (also read by other agents)
        ("cursor", ".cursor/skills/proof"),     // Cursor
        ("copilot", ".copilot/skills/proof"),   // GitHub Copilot
    ]

    /// The skill folders for `--agent` values; `all` means every known agent.
    public static func skillDirs(agents: [String], home: String = NSHomeDirectory()) throws -> [String] {
        let names = agents.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
        if names.contains("all") { return agentSkillDirs.map { Paths.join(home, $0.dir) } }
        return try names.map { name in
            guard let entry = agentSkillDirs.first(where: { $0.agent == name }) else {
                throw ProofError.message("unknown agent '\(name)'. Known: \(agentSkillDirs.map(\.agent).joined(separator: ", ")), all. "
                                         + "For another agent: --skill-dir <its skills folder>/proof")
            }
            return Paths.join(home, entry.dir)
        }
    }

    /// The resources next to an executable: `../share/proof` for a Homebrew or `PREFIX` install
    /// (`<prefix>/bin/proof`), `../Resources` inside an app bundle (`Contents/Helpers/proof`), or the repo
    /// when run from a checkout (`.build/<config>/proof`). Symlinks are resolved first, so
    /// `/opt/homebrew/bin/proof → Cellar/proof/<version>/bin/proof` works.
    public static func resources(executable: String) -> Resources? {
        let exe = Paths.canonical(executable)
        var dir = (exe as NSString).deletingLastPathComponent
        let prefix = (dir as NSString).deletingLastPathComponent
        for root in [Paths.join(prefix, "share", "proof"), Paths.join(prefix, "Resources")] {
            let candidate = Resources(root: root)
            if candidate.isComplete { return candidate }
        }
        // A checkout: walk up from .build/arm64-apple-macosx/release to the package root.
        for _ in 0..<6 {
            let candidate = Resources(root: dir)
            if candidate.isComplete { return candidate }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    public struct Result: Report {
        public let runner: String
        public let skills: [String]
        public let source: String
        public var text: String {
            (["installed runner sources  \(runner)"] + skills.map { "installed agent skill    \($0)" }
             + ["from                     \(source)", "start a new agent session so it picks the skill up"])
                .joined(separator: "\n")
        }
    }

    /// Copies the runner sources to `runnerDest` (replacing what was there) and SKILL.md into each of
    /// `skillDirs`. Running it twice gives the same result.
    public static func install(_ resources: Resources, runnerDest: String = Paths.runnerSource,
                               skillDirs: [String] = [defaultSkillDir]) throws -> Result {
        guard resources.isComplete else {
            throw ProofError.message("no runner sources or skill in \(resources.root)")
        }
        try installRunner(resources, runnerDest: runnerDest)
        let fm = FileManager.default
        var skills: [String] = []
        for dir in skillDirs {
            try Paths.ensureDir(dir)
            let skill = Paths.join(dir, "SKILL.md")
            try? fm.removeItem(atPath: skill)
            try fm.copyItem(atPath: resources.skill, toPath: skill)
            skills.append(skill)
        }
        return Result(runner: runnerDest, skills: skills, source: resources.root)
    }

    /// Whether the runner sources at `runnerDest` are the ones in `resources` (same files, same contents).
    public static func runnerMatches(_ resources: Resources, runnerDest: String = Paths.runnerSource) -> Bool {
        let fm = FileManager.default
        guard let files = fm.enumerator(atPath: resources.runner) else { return false }
        for case let file as String in files where !file.contains("xcuserdata") {
            let source = Paths.join(resources.runner, file)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source, isDirectory: &isDir), !isDir.boolValue else { continue }
            if !fm.contentsEqual(atPath: source, andPath: Paths.join(runnerDest, file)) { return false }
        }
        return true
    }

    /// Copies only the runner sources (used when ~/.proof was cleared; the skill is left alone).
    public static func installRunner(_ resources: Resources, runnerDest: String = Paths.runnerSource) throws {
        let fm = FileManager.default
        try Paths.ensureDir((runnerDest as NSString).deletingLastPathComponent)
        // Copy to a sibling first, then swap, so a failed copy never leaves the runner half-installed.
        let staging = runnerDest + ".new"
        try? fm.removeItem(atPath: staging)
        try fm.copyItem(atPath: resources.runner, toPath: staging)
        try? fm.removeItem(atPath: runnerDest)
        try fm.moveItem(atPath: staging, toPath: runnerDest)
    }
}

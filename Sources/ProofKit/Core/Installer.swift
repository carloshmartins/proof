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

    /// Where the agent skill goes unless `--skill-dir` says otherwise.
    public static var defaultSkillDir: String {
        Paths.join(NSHomeDirectory(), ".claude", "skills", "proof")
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
        public let skill: String
        public let source: String
        public var text: String {
            ["installed runner sources  \(runner)", "installed agent skill    \(skill)", "from                     \(source)"]
                .joined(separator: "\n")
        }
    }

    /// Copies the runner sources to `runnerDest` (replacing what was there) and SKILL.md into `skillDir`.
    /// Running it twice gives the same result.
    public static func install(_ resources: Resources, runnerDest: String = Paths.runnerSource,
                               skillDir: String = defaultSkillDir) throws -> Result {
        guard resources.isComplete else {
            throw ProofError.message("no runner sources or skill in \(resources.root)")
        }
        try installRunner(resources, runnerDest: runnerDest)
        let fm = FileManager.default
        try Paths.ensureDir(skillDir)
        let skill = Paths.join(skillDir, "SKILL.md")
        try? fm.removeItem(atPath: skill)
        try fm.copyItem(atPath: resources.skill, toPath: skill)
        return Result(runner: runnerDest, skill: skill, source: resources.root)
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

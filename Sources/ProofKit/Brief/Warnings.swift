import Foundation

/// The warnings a branch adds compared with another branch.
///
/// After every build or test that compiles, the branch's warnings are saved in its session
/// (`results/warnings.json`). xcodebuild only reports warnings for the files it recompiles, so the saved list
/// is merged: files compiled this time get their new warnings, the others keep the ones saved before.
/// A warning is "new" when its file and message appear more often than on the other branch; line numbers
/// are ignored, so code moving around doesn't count.
public enum Warnings {
    static func path(_ sessionDir: String) -> String { Paths.join(sessionDir, "results", "warnings.json") }

    public static func load(sessionDir: String) -> [Diagnostic]? {
        Output.readJSON([Diagnostic].self, from: path(sessionDir))
    }

    public static func save(_ warnings: [Diagnostic], sessionDir: String) {
        try? Paths.ensureDir(Paths.join(sessionDir, "results"))
        try? Output.writeJSON(warnings, to: path(sessionDir))
    }

    /// The branch's full warning list after a build: `fresh` replaces what `previous` had for every file in
    /// `compiled` (and warnings without a file); everything else in `previous` is kept.
    public static func merge(previous: [Diagnostic], fresh: [Diagnostic], compiled: Set<String>) -> [Diagnostic] {
        let kept = previous.filter { w in w.file.map { !compiled.contains($0) } ?? false }
        let freshKeys = Set(fresh.map(key))
        return kept.filter { !freshKeys.contains(key($0)) } + fresh
    }

    /// Warnings in `current` beyond what `base` has, compared by file and message.
    public static func added(current: [Diagnostic], base: [Diagnostic]) -> [Diagnostic] {
        var budget: [String: Int] = [:]
        for w in base { budget[key(w), default: 0] += 1 }
        var out: [Diagnostic] = []
        for w in current {
            let k = key(w)
            if let n = budget[k], n > 0 { budget[k] = n - 1 } else { out.append(w) }
        }
        return out
    }

    static func key(_ w: Diagnostic) -> String { (w.file ?? "") + "\u{0}" + w.message }

    /// Source files xcodebuild compiled, from its raw output, relative to `root` like diagnostics are.
    public static func compiledFiles(log: String, root: String?) -> Set<String> {
        let prefixes = ["SwiftCompile ", "CompileSwift ", "CompileC "]
        let extensions = [".swift", ".m", ".mm", ".c", ".cc", ".cpp"]
        var files: Set<String> = []
        for raw in log.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard prefixes.contains(where: line.hasPrefix) else { continue }
            let head = line.components(separatedBy: " (in target").first ?? line
            for token in head.replacingOccurrences(of: "\\ ", with: "\u{0}").split(separator: " ")
            where token.hasPrefix("/") && extensions.contains(where: { token.hasSuffix($0) }) {
                let path = String(token).replacingOccurrences(of: "\u{0}", with: " ")
                files.insert(root.map { Paths.relative(path, to: $0) } ?? path)
            }
        }
        return files
    }

    /// Updates the branch's saved warnings after a build that compiled, and returns the full list.
    @discardableResult
    public static func record(_ brief: BriefResult, allWarnings: [Diagnostic], log: String, root: String, sessionDir: String) -> [Diagnostic]? {
        guard brief.errors.isEmpty else { return nil }   // a build that stopped early has a partial list
        let merged = merge(previous: load(sessionDir: sessionDir) ?? [], fresh: allWarnings,
                           compiled: compiledFiles(log: log, root: root))
        save(merged, sessionDir: sessionDir)
        return merged
    }
}

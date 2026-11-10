import Foundation

/// How much of what a branch changed the tests run: "12 of 40 changed lines run by tests", and which
/// lines don't, so an agent knows which tests to write. Changed lines are the diff from where the branch
/// left its base (uncommitted and new files included); coverage comes from the test run's `.xcresult`.
public struct ChangedCoverage: Codable, Equatable {
    public struct FileGap: Codable, Equatable {
        public let file: String          // repo-relative
        public let uncovered: [Int]
        public var ranges: String { ChangedCoverage.ranges(uncovered) }
    }

    public let base: String
    public let executable: Int           // changed lines the compiler made code for
    public let covered: Int
    public let gaps: [FileGap]

    public var percent: Int { executable == 0 ? 100 : Int((Double(covered) / Double(executable) * 100).rounded()) }

    public var text: String {
        guard executable > 0 else { return "COVERAGE no changed code lines vs \(base)" }
        var out = ["COVERAGE \(covered) of \(executable) changed lines run by tests (\(percent)%) vs \(base)"]
        for g in gaps.prefix(15) { out.append("untested  \(g.file): \(g.ranges)") }
        if gaps.count > 15 { out.append("… +\(gaps.count - 15) more files") }
        return out.joined(separator: "\n")
    }

    /// [3, 4, 5, 9] → "3-5, 9"
    static func ranges(_ lines: [Int]) -> String {
        var parts: [String] = []
        var i = 0
        let sorted = lines.sorted()
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
            parts.append(i == j ? "\(sorted[i])" : "\(sorted[i])-\(sorted[j])")
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }
}

public enum Coverage {
    static let sourceExtensions = ["swift", "m", "mm", "c", "cc", "cpp"]

    /// Lines added or changed per file, from `git diff -U0` output (new-file side).
    public static func changedLines(diff: String) -> [String: Set<Int>] {
        var out: [String: Set<Int>] = [:]
        var file: String?
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++ ") {
                let path = line.dropFirst(4)
                file = path == "/dev/null" ? nil : String(path.hasPrefix("b/") ? path.dropFirst(2) : path)
            } else if line.hasPrefix("@@"), let file,
                      let plus = line.split(separator: " ").first(where: { $0.hasPrefix("+") }) {
                let nums = plus.dropFirst().split(separator: ",").compactMap { Int($0) }
                guard let start = nums.first else { continue }
                let count = nums.count > 1 ? nums[1] : 1
                if count > 0 { out[file, default: []].formUnion(start..<(start + count)) }
            }
        }
        return out
    }

    /// Per-line coverage for one file from `xccov view --archive --json --file`: line → executed count,
    /// only for executable lines.
    public static func lineCounts(json: String) -> [Int: Int] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let lines = obj.values.first as? [[String: Any]] else { return [:] }
        var out: [Int: Int] = [:]
        for l in lines where l["isExecutable"] as? Bool == true {
            if let n = l["line"] as? Int { out[n] = l["executionCount"] as? Int ?? 0 }
        }
        return out
    }

    /// Source files of the app's targets (test bundles left out) from `xccov view --report --json`.
    public static func appFiles(reportJSON: String) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(reportJSON.utf8)) as? [String: Any] else { return [] }
        return (obj["targets"] as? [[String: Any]] ?? [])
            .filter { !($0["name"] as? String ?? "").hasSuffix(".xctest") }
            .flatMap { ($0["files"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String } }
    }

    /// Puts it together. `coverage` maps a repo-relative file to its line counts.
    public static func report(base: String, changed: [String: Set<Int>], coverage: [String: [Int: Int]]) -> ChangedCoverage {
        var executable = 0, covered = 0
        var gaps: [ChangedCoverage.FileGap] = []
        for file in changed.keys.sorted() {
            guard let counts = coverage[file] else { continue }
            let lines = changed[file]!.filter { counts[$0] != nil }
            executable += lines.count
            let untested = lines.filter { counts[$0] == 0 }
            covered += lines.count - untested.count
            if !untested.isEmpty { gaps.append(.init(file: file, uncovered: untested.sorted())) }
        }
        return ChangedCoverage(base: base, executable: executable, covered: covered, gaps: gaps)
    }

    /// Changed lines of `root` since it left `base`, uncommitted work and new files included.
    public static func changedSince(base: String, root: String) throws -> [String: Set<Int>] {
        let ref = try StackRunner.resolveRef(base, cwd: root)
        let mergeBase = try Shell.checked(["git", "merge-base", ref, "HEAD"], cwd: root)
        let globs = sourceExtensions.map { "*.\($0)" }
        let diff = try Shell.checked(["git", "diff", "-U0", "--no-color", "--no-ext-diff", mergeBase, "--"] + globs, cwd: root)
        var changed = changedLines(diff: diff)
        let untracked = try Shell.checked(["git", "ls-files", "--others", "--exclude-standard", "--"] + globs, cwd: root)
        for file in untracked.split(separator: "\n").map(String.init) {
            let count = ((try? String(contentsOfFile: Paths.join(root, file), encoding: .utf8)) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false).count
            if count > 0 { changed[file] = Set(1...count) }
        }
        return changed
    }

    /// Reads the bundle's coverage for the changed files and builds the report. Nil when the bundle has none.
    public static func compute(bundle: String, base: String, root: String) -> ChangedCoverage? {
        guard let changed = try? changedSince(base: base, root: root),
              let report = try? Shell.run(["xcrun", "xccov", "view", "--report", "--json", bundle]), report.ok else { return nil }
        let files = appFiles(reportJSON: report.stdout)
        var coverage: [String: [Int: Int]] = [:]
        for file in changed.keys {
            // xccov paths can differ from git's by a symlink (/tmp vs /private/tmp): match on the repo-relative end.
            guard let path = files.first(where: { $0.hasSuffix("/" + file) }),
                  let r = try? Shell.run(["xcrun", "xccov", "view", "--archive", "--json", "--file", path, bundle]), r.ok else { continue }
            coverage[file] = lineCounts(json: r.stdout)
        }
        return Coverage.report(base: base, changed: changed, coverage: coverage)
    }
}

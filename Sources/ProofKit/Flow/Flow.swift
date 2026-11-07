import Foundation

/// A named, replayable sequence of steps stored in ~/.proof/flows/<repo>/<name>.flow.
public struct Flow {
    public let name: String
    public let path: String
    public let steps: [FlowStep]

    public static func directory(repo: String) -> String { Paths.join(Paths.home, "flows", repo) }

    /// Accepts a flow name (looked up for this repo) or a path to a .flow file.
    public static func resolvePath(_ nameOrPath: String, repo: String) -> String {
        if nameOrPath.hasSuffix(".flow") || nameOrPath.contains("/") {
            return nameOrPath.hasPrefix("/") ? nameOrPath : Paths.join(FileManager.default.currentDirectoryPath, nameOrPath)
        }
        return Paths.join(directory(repo: repo), nameOrPath + ".flow")
    }

    public static func load(_ nameOrPath: String, repo: String) throws -> Flow {
        try load(nameOrPath, repo: repo, depth: 0)
    }

    static func load(_ nameOrPath: String, repo: String, depth: Int) throws -> Flow {
        guard depth < 8 else { throw ProofError.message("include nesting too deep (cycle?) at \(nameOrPath)") }
        let path = resolvePath(nameOrPath, repo: repo)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ProofError.message("flow not found: \(path). See `proof flow list`")
        }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var steps: [FlowStep] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            guard let step = try FlowStep.parse(line: raw, line: i + 1) else { continue }
            if step.action == "include" {
                guard let sub = step.positional.first else { throw ProofError.message("line \(i + 1): include needs a flow name") }
                steps += try load(sub, repo: repo, depth: depth + 1).steps
            } else {
                steps.append(step)
            }
        }
        return Flow(name: name, path: path, steps: steps)
    }

    public static func parse(_ text: String, name: String = "inline") throws -> Flow {
        let steps = try text.components(separatedBy: "\n").enumerated().compactMap { try FlowStep.parse(line: $1, line: $0 + 1) }
        return Flow(name: name, path: "", steps: steps)
    }

    public static func save(name: String, lines: [String], repo: String, header: [String] = [], overwrite: Bool) throws -> String {
        let dir = directory(repo: repo)
        try Paths.ensureDir(dir)
        let path = Paths.join(dir, Paths.sanitize(name) + ".flow")
        if Paths.exists(path) && !overwrite { throw ProofError.message("flow exists: \(path). Use --force to overwrite") }
        let text = (header.map { "# " + $0 } + lines).joined(separator: "\n") + "\n"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    public static func list(repo: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory(repo: repo))) ?? []
        return files.filter { $0.hasSuffix(".flow") }.map { String($0.dropLast(5)) }.sorted()
    }
}

/// Records successful `proof ui …` and `proof snap` commands into a draft flow.
public enum Recorder {
    public struct State: Codable {
        public let repo: String
        public let branch: String
        public let started: Date
        public var lines: [String]
    }

    static var file: String { Paths.join(Paths.home, "recording.json") }

    public static func state() -> State? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        return try? dec.decode(State.self, from: data)
    }

    static func write(_ s: State) throws {
        try Paths.ensureDir(Paths.home)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        try enc.encode(s).write(to: URL(fileURLWithPath: file))
    }

    public static func start(_ ctx: Context) throws {
        try write(State(repo: ctx.repo, branch: ctx.branch, started: Date(), lines: []))
    }

    /// Appends a step when a recording is active for this repo. Never fails the command itself.
    public static func record(_ step: FlowStep, repo: String) {
        guard var s = state(), s.repo == repo else { return }
        s.lines.append(step.line)
        try? write(s)
    }

    /// Drops the last n recorded steps (undo a mistaken tap).
    public static func undo(_ n: Int) throws -> State {
        guard var s = state() else { throw ProofError.message("no recording in progress") }
        s.lines.removeLast(min(n, s.lines.count))
        try write(s)
        return s
    }

    public static func stop() -> State? {
        let s = state()
        try? FileManager.default.removeItem(atPath: file)
        return s
    }
}

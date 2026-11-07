import Foundation

/// Append-only log of what proof did, one JSON object per line, per branch session:
///   ~/.proof/sessions/<repo>/<branch>/events.jsonl
/// plus ~/.proof/current.json pointing at the most recently active session.
/// A UI (or `tail -f`) can follow progress without talking to the CLI.
public struct ProofEvent: Codable, Equatable {
    public var time: Date
    public var kind: String          // build | test | stack | step | snap | flow | video | runner
    public var name: String          // step line, flow name, snap name…
    public var status: String        // started | ok | failed
    public var detail: String?
    public var duration: Double?
    public var file: String?         // screenshot / video / report path
    public var flow: String?         // flow this step belongs to
    public var index: Int?           // step index within the flow
    public var total: Int?
    public var target: String?       // acted element, e.g. `button #timer.length.picker`
    public var label: String?        // its accessibility label
    public var frame: [Int]?         // its frame in points: x, y, width, height
    public var screen: [Int]?        // app frame in points: width, height (maps screenshots to points)

    public init(kind: String, name: String, status: String, detail: String? = nil, duration: Double? = nil,
                file: String? = nil, flow: String? = nil, index: Int? = nil, total: Int? = nil,
                target: StepTarget? = nil) {
        self.time = Date(); self.kind = kind; self.name = name; self.status = status; self.detail = detail
        self.duration = duration; self.file = file; self.flow = flow; self.index = index; self.total = total
        if let target {
            self.target = target.selector; self.label = target.label; self.frame = target.frame; self.screen = target.screen
        }
    }
}

/// Written once per session folder so viewers know the real branch name (folder names are sanitised)
/// and where to run the CLI from.
public struct SessionMeta: Codable, Equatable {
    public let repo: String
    public let branch: String
    public let root: String          // main checkout
    public init(repo: String, branch: String, root: String) { self.repo = repo; self.branch = branch; self.root = root }

    public static func file(_ sessionDir: String) -> String { Paths.join(sessionDir, "session.json") }
    public static func load(_ sessionDir: String) -> SessionMeta? { Output.readJSON(SessionMeta.self, from: file(sessionDir)) }
}

public enum Events {
    public struct Current: Codable {
        public let repo: String
        public let branch: String
        public let session: String
        public let updated: Date
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public static func file(_ sessionDir: String) -> String { Paths.join(sessionDir, "events.jsonl") }

    /// Best effort: logging must never break a command.
    public static func append(_ event: ProofEvent, ctx: Context) {
        let dir = ctx.sessionDir
        try? Paths.ensureDir(dir)
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)
        if !Paths.exists(SessionMeta.file(dir)) {
            try? Output.writeJSON(SessionMeta(repo: ctx.repo, branch: ctx.branch, root: ctx.mainRoot), to: SessionMeta.file(dir))
        }
        let path = file(dir)
        if !Paths.exists(path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        }
        let current = Current(repo: ctx.repo, branch: ctx.branch, session: dir, updated: event.time)
        if let c = try? encoder.encode(current) { try? c.write(to: URL(fileURLWithPath: Paths.join(Paths.home, "current.json"))) }
    }

    /// The most recently active session, for UIs following along.
    public static func current() -> Current? {
        guard let data = FileManager.default.contents(atPath: Paths.join(Paths.home, "current.json")) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Current.self, from: data)
    }

    public static func load(_ sessionDir: String) -> [ProofEvent] {
        guard let text = try? String(contentsOfFile: file(sessionDir), encoding: .utf8) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? dec.decode(ProofEvent.self, from: Data($0.utf8)) }
    }
}

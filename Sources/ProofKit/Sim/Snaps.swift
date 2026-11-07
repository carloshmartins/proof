import Foundation

public struct SnapRecord: Codable, Report {
    public let name: String
    public let screenshot: String      // absolute path
    public let tree: String            // absolute path to tree text
    public let branch: String
    public let sha: String
    public let time: Date
    public var compareBranch: String?
    public var diff: [String]?
    public var missingIdentifiers: Int
    public var nodes: String? = nil    // absolute path to the nodes with frames (SnapNodes JSON)
    public var device: String? = nil   // "iPhone 16 Pro · iOS 26.1"

    public var text: String {
        var out = ["snap \(name) → \(screenshot)"]
        if missingIdentifiers > 0 { out.append("\(missingIdentifiers) interactive element(s) without accessibilityIdentifier") }
        if let compareBranch {
            if let diff, !diff.isEmpty {
                out.append("tree diff vs \(compareBranch):")
                out.append(contentsOf: diff.prefix(40))
                if diff.count > 40 { out.append("… +\(diff.count - 40) lines (see packet)") }
            } else if diff != nil {
                out.append("no tree changes vs \(compareBranch)")
            } else {
                out.append("no '\(name)' snap on \(compareBranch) to compare with · put it in a flow and run "
                           + "`proof flow run <flow> --compare \(compareBranch)`: proof snaps \(compareBranch) for you")
            }
        }
        return out.joined(separator: "\n")
    }
}

/// What `snaps/<name>.json` holds: the tree with frames, and the screen size in points.
public struct SnapNodes: Codable, Equatable {
    public var screen: [Int]?
    public var nodes: [UINode]
    public init(screen: [Int]?, nodes: [UINode]) { self.screen = screen; self.nodes = nodes }

    public static func load(_ path: String?) -> SnapNodes? { path.flatMap { Output.readJSON(SnapNodes.self, from: $0) } }
}

public enum Snaps {
    static func indexPath(_ sessionDir: String) -> String { Paths.join(sessionDir, "snaps", "index.json") }

    public static func load(sessionDir: String) -> [SnapRecord] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = FileManager.default.contents(atPath: indexPath(sessionDir)) else { return [] }
        return (try? dec.decode([SnapRecord].self, from: data)) ?? []
    }

    static func save(_ records: [SnapRecord], sessionDir: String) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(records).write(to: URL(fileURLWithPath: indexPath(sessionDir)))
    }

    /// Screenshot + accessibility tree of the current screen, stored in this branch's session.
    /// Re-snapping a name replaces it, so snaps track the latest state of each screen.
    public static func take(_ ctx: Context, name: String, compareWith: String?) throws -> SnapRecord {
        let response = try Runner.command("/tree", [:], simulator: ctx.config.simulator)
        let nodes = try UITree.decode(response)
        guard let udid = Runner.state()?.udid else { throw ProofError.message("runner not running") }

        let dir = Paths.join(ctx.sessionDir, "snaps")
        try Paths.ensureDir(dir)
        let file = Paths.sanitize(name)
        let png = Paths.join(dir, file + ".png")
        let txt = Paths.join(dir, file + ".txt")
        let json = Paths.join(dir, file + ".json")
        try Shell.checked(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", png])
        let treeText = UITree.render(nodes)
        try treeText.write(toFile: txt, atomically: true, encoding: .utf8)
        try Output.writeJSON(SnapNodes(screen: UITree.screen(response), nodes: nodes), to: json)

        var record = SnapRecord(name: name, screenshot: png, tree: txt, branch: ctx.branch,
                                sha: (try? Git.shortSHA(cwd: ctx.root)) ?? "?", time: Date(),
                                compareBranch: nil, diff: nil,
                                missingIdentifiers: UITree.missingIdentifiers(nodes).count, nodes: json,
                                device: ((try? Simulators.list()) ?? []).first { $0.udid == udid }?.title)
        if let other = BaseBranch.resolve(compareWith, ctx: ctx) {
            record.compareBranch = other
            let otherDir = Paths.session(repo: ctx.repo, branch: other)
            if let base = load(sessionDir: otherDir).first(where: { $0.name == name }),
               let baseText = try? String(contentsOfFile: base.tree, encoding: .utf8) {
                record.diff = LineDiff.diff(baseText.components(separatedBy: "\n"), treeText.components(separatedBy: "\n"))
            }
        }
        var all = load(sessionDir: ctx.sessionDir).filter { $0.name != name }
        all.append(record)
        try save(all, sessionDir: ctx.sessionDir)
        Events.append(ProofEvent(kind: "snap", name: name, status: "ok",
                                 detail: record.diff.map { "\($0.count) tree lines changed vs \(record.compareBranch ?? "")" }, file: png), ctx: ctx)
        return record
    }
}

import Foundation

public struct UINode: Codable, Equatable {
    public var type: String
    public var depth: Int
    public var frame: [Int]?
    public var id: String?
    public var label: String?
    public var value: String?
    public var placeholder: String?
    public var enabled: Bool?
    public var selected: Bool?

    public init(type: String, depth: Int, frame: [Int]? = nil, id: String? = nil, label: String? = nil,
                value: String? = nil, placeholder: String? = nil, enabled: Bool? = nil, selected: Bool? = nil) {
        self.type = type; self.depth = depth; self.frame = frame; self.id = id; self.label = label
        self.value = value; self.placeholder = placeholder; self.enabled = enabled; self.selected = selected
    }

    /// Compact single-line form: `button #login.submit "Log in" [disabled]`
    public func line(frames: Bool = false) -> String {
        var s = String(repeating: "  ", count: depth) + type
        if let id { s += " #\(id)" }
        if let label { s += " \"\(label)\"" }
        if let value { s += " =\(value.count > 60 ? String(value.prefix(60)) + "…" : value)" }
        if let placeholder, value == nil { s += " (\(placeholder))" }
        if enabled == false { s += " [disabled]" }
        if selected == true { s += " [selected]" }
        if frames, let f = frame, f.count == 4 { s += " @\(f[0]),\(f[1]) \(f[2])x\(f[3])" }
        return s
    }
}

/// The element a step acted on, as the runner reports it (`target` in its response).
public struct StepTarget: Codable, Equatable {
    public var type: String
    public var id: String?
    public var label: String?
    public var frame: [Int]?
    public var screen: [Int]?

    public init(type: String, id: String? = nil, label: String? = nil, frame: [Int]? = nil, screen: [Int]? = nil) {
        self.type = type; self.id = id; self.label = label; self.frame = frame; self.screen = screen
    }

    /// `button #timer.length.picker`, or `button "Start"` when it has no identifier.
    public var selector: String {
        if let id, !id.isEmpty { return "\(type) #\(id)" }
        if let label, !label.isEmpty { return "\(type) \"\(label)\"" }
        return type
    }

    /// From a runner response's `target` object; nil when the step had no element.
    public static func decode(_ response: [String: Any]) -> StepTarget? {
        guard let raw = response["target"] as? [String: Any], let type = raw["type"] as? String else { return nil }
        func ints(_ v: Any?) -> [Int]? { (v as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? Int) } }
        return StepTarget(type: type, id: (raw["id"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                          label: (raw["label"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                          frame: ints(raw["frame"]), screen: UITree.screen(response))
    }
}

/// The app's frame in points, so screenshots (pixels) map to element frames (points).
public struct ScreenSize: Codable, Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public enum UITree {
    /// `screen: {width, height}` from a runner response, as `[width, height]`.
    public static func screen(_ response: [String: Any]) -> [Int]? {
        guard let s = response["screen"] as? [String: Any],
              let w = (s["width"] as? NSNumber)?.intValue, let h = (s["height"] as? NSNumber)?.intValue else { return nil }
        return [w, h]
    }

    public static func decode(_ response: [String: Any]) throws -> [UINode] {
        let raw = response["nodes"] ?? []
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode([UINode].self, from: data)
    }

    /// Drops the application/window wrappers so depth starts at the content.
    public static func render(_ nodes: [UINode], frames: Bool = false, interactiveOnly: Bool = false) -> String {
        let shown = interactiveOnly ? nodes.filter { interactiveTypes.contains($0.type) } : nodes
        return shown.map { n in
            var copy = n
            if interactiveOnly { copy.depth = 0 }
            return copy.line(frames: frames)
        }.joined(separator: "\n")
    }

    /// Nodes no deeper than `depth`, relative to the shallowest node.
    public static func limit(_ nodes: [UINode], depth: Int) -> [UINode] {
        let top = nodes.map(\.depth).min() ?? 0
        return nodes.filter { $0.depth - top <= depth }
    }

    public static let interactiveTypes: Set<String> = [
        "button", "textfield", "securefield", "searchfield", "textview", "switch", "toggle", "slider",
        "stepper", "segmented", "link", "cell", "picker", "pickerwheel", "datepicker", "menuitem", "tab",
    ]

    /// Index (in `nodes`) of the element under a point, in points. Prefers the smallest interactive
    /// element; falls back to the smallest element with an id or label.
    public static func hitTest(_ nodes: [UINode], x: Double, y: Double) -> Int? {
        func contains(_ n: UINode) -> Bool {
            guard let f = n.frame, f.count == 4, f[2] > 0, f[3] > 0 else { return false }
            return x >= Double(f[0]) && x <= Double(f[0] + f[2]) && y >= Double(f[1]) && y <= Double(f[1] + f[3])
        }
        func area(_ i: Int) -> Int { (nodes[i].frame?[2] ?? 0) * (nodes[i].frame?[3] ?? 0) }
        let hits = nodes.indices.filter { contains(nodes[$0]) && !["app", "window"].contains(nodes[$0].type) }
        let interactive = hits.filter { interactiveTypes.contains(nodes[$0].type) }
        if let best = interactive.min(by: { area($0) < area($1) }) { return best }
        let named = hits.filter { !(nodes[$0].id ?? "").isEmpty || !(nodes[$0].label ?? "").isEmpty }
        return named.min(by: { area($0) < area($1) })
    }

    /// The most stable selector for a node: unique id, then unique label, then type+label(+index),
    /// then the frame centre as coordinates.
    public static func selectorTokens(for index: Int, in nodes: [UINode]) -> [String] {
        let n = nodes[index]
        let before = nodes[..<index]
        if let id = n.id, !id.isEmpty {
            let same = nodes.filter { $0.id == id }.count
            if same == 1 { return ["--id", id] }
            return ["--id", id, "--index", String(before.filter { $0.id == id }.count)]
        }
        if let label = n.label, !label.isEmpty {
            if nodes.filter({ $0.label == label }).count == 1 { return ["--label", label] }
            let sameTyped = nodes.filter { $0.label == label && $0.type == n.type }.count
            if sameTyped == 1 { return ["--type", n.type, "--label", label] }
            return ["--type", n.type, "--label", label, "--index", String(before.filter { $0.label == label && $0.type == n.type }.count)]
        }
        if let f = n.frame, f.count == 4 {
            return ["--x", String(f[0] + f[2] / 2), "--y", String(f[1] + f[3] / 2)]
        }
        return []
    }

    /// Runtime accessibility audit: interactive elements without an identifier.
    public static func missingIdentifiers(_ nodes: [UINode]) -> [UINode] {
        nodes.filter { interactiveTypes.contains($0.type) && ($0.id ?? "").isEmpty }
    }
}

/// The step `proof ui at X Y --as …` performs for the element under the point.
public enum AtStep {
    /// `tap` and `expect` target the selector; `snap:<name>` snaps the whole screen.
    public static func tokens(as action: String, selector: [String]) throws -> [String] {
        switch action {
        case "tap": return ["tap"] + selector
        case "expect":
            guard !selector.contains("--x") else { throw ProofError.message("nothing to expect at that point: no element with an id or label") }
            return ["expect"] + selector
        case let a where a.hasPrefix("snap:"):
            let name = String(a.dropFirst(5))
            guard !name.isEmpty else { throw ProofError.message("--as snap:<name> needs a name") }
            return ["snap", name]
        default:
            throw ProofError.message("--as must be tap, expect or snap:<name>, got \(action)")
        }
    }
}

/// One difference between two accessibility trees.
public struct TreeChange: Codable, Equatable {
    public enum Kind: String, Codable { case added, removed, changed }
    public let kind: Kind
    public let node: UINode          // the new node (the old one when removed)
    public let old: UINode?          // the old node when changed
    public var frame: [Int]? { node.frame }

    public init(kind: Kind, node: UINode, old: UINode? = nil) { self.kind = kind; self.node = node; self.old = old }

    /// `+ button #timer.preset.25 "25" [selected]`, `- text "15:00"`, `~ switch #x =1 (was =0)`
    public var line: String {
        let n = node.line().trimmingCharacters(in: .whitespaces)
        switch kind {
        case .added: return "+ " + n
        case .removed: return "- " + n
        case .changed: return "~ " + n + (old.map { " (was \($0.line().trimmingCharacters(in: .whitespaces)))" } ?? "")
        }
    }
}

/// Structural diff of two node lists: nodes match by identifier, else by type + label + occurrence.
/// Frames don't count as changes (layout moves are noise); the new frame is reported for outlines.
public enum TreeDiff {
    static func key(_ n: UINode, _ seen: inout [String: Int]) -> String {
        let base = (n.id ?? "").isEmpty ? "t:\(n.type)|\(n.label ?? "")" : "id:\(n.id!)"
        let k = seen[base, default: 0]
        seen[base] = k + 1
        return "\(base)#\(k)"
    }

    static func comparable(_ n: UINode) -> Bool {
        !["app", "window"].contains(n.type) && (!(n.id ?? "").isEmpty || !(n.label ?? "").isEmpty || n.value != nil)
    }

    public static func changes(old: [UINode], new: [UINode]) -> [TreeChange] {
        var seenOld: [String: Int] = [:], seenNew: [String: Int] = [:]
        let o = old.filter(comparable).map { (key($0, &seenOld), $0) }
        let n = new.filter(comparable).map { (key($0, &seenNew), $0) }
        let oldByKey = Dictionary(o, uniquingKeysWith: { a, _ in a })
        let newKeys = Set(n.map(\.0))
        var out: [TreeChange] = []
        for (k, node) in n {
            guard let before = oldByKey[k] else { out.append(TreeChange(kind: .added, node: node)); continue }
            if before.type != node.type || before.label != node.label || before.value != node.value
                || (before.enabled ?? true) != (node.enabled ?? true) || (before.selected ?? false) != (node.selected ?? false) {
                out.append(TreeChange(kind: .changed, node: node, old: before))
            }
        }
        for (k, node) in o where !newKeys.contains(k) { out.append(TreeChange(kind: .removed, node: node)) }
        return out
    }
}

/// Line diff (LCS). Returns only changed lines, prefixed "+ " / "- ".
public enum LineDiff {
    public static func diff(_ old: [String], _ new: [String], limit: Int = 200) -> [String] {
        let n = old.count, m = new.count
        guard n * m <= 4_000_000 else {
            // Too large for LCS: fall back to set difference.
            let o = Set(old), nw = Set(new)
            return (old.filter { !nw.contains($0) }.map { "- " + $0 } + new.filter { !o.contains($0) }.map { "+ " + $0 }).prefix(limit).map { $0 }
        }
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < n || j < m {
            if out.count >= limit { out.append("… diff truncated"); break }
            if i < n, j < m, old[i] == new[j] { i += 1; j += 1 }
            else if i < n, j == m || lcs[i + 1][j] >= lcs[i][j + 1] { out.append("- " + old[i]); i += 1 }
            else { out.append("+ " + new[j]); j += 1 }
        }
        return out
    }
}

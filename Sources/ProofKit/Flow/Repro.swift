import Foundation

/// Bug reports as flows: export a recorded flow to paste into an issue, and replay the flow from an issue.
public enum Repro {
    /// A flow as one self-contained file: includes expanded, and a header saying where it was recorded and
    /// which variables it needs. `markdown` wraps it in a fenced `flow` block for an issue.
    public static func export(_ flow: Flow, branch: String, sha: String, device: String?, markdown: Bool) -> String {
        var header = ["# proof flow \(flow.name)", "# recorded on \(branch) (\(sha))" + (device.map { " · \($0)" } ?? "")]
        let vars = variables(flow)
        if !vars.isEmpty { header.append("# needs " + vars.map { "--var \($0)=…" }.joined(separator: " ")) }
        header.append("# replay: proof repro <this issue>   or   proof flow run <file>")
        let body = (header + flow.steps.map(\.line)).joined(separator: "\n")
        return markdown ? "```flow\n\(body)\n```" : body
    }

    /// The `${NAME}` variables a flow uses, in order of first use.
    public static func variables(_ flow: Flow) -> [String] {
        var seen: [String] = []
        for step in flow.steps {
            for text in step.positional + step.options.map(\.value) {
                var rest = Substring(text)
                while let start = rest.range(of: "${"), let end = rest[start.upperBound...].firstIndex(of: "}") {
                    let name = String(rest[start.upperBound..<end])
                    if !seen.contains(name) { seen.append(name) }
                    rest = rest[rest.index(after: end)...]
                }
            }
        }
        return seen
    }

    /// The flow in an issue body: the first ```flow block, else the first fenced block whose every line is a
    /// flow step. Nil when there's none.
    public static func extractFlow(markdown: String) -> String? {
        var blocks: [(info: String, body: [String])] = []
        var current: (info: String, body: [String])?
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = current { blocks.append(c); current = nil }
                else { current = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased(), []) }
            } else if current != nil {
                current!.body.append(raw)
            }
        }
        if let flow = blocks.first(where: { $0.info == "flow" }) { return flow.body.joined(separator: "\n") }
        return blocks.first { block in
            let steps = block.body.compactMap { try? FlowStep.parse(line: $0) }
            let nonEmpty = block.body.filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#")
            }
            return !nonEmpty.isEmpty && steps.count == nonEmpty.count
        }?.body.joined(separator: "\n")
    }

    /// "123", "#123" or ".../issues/123" → 123.
    public static func issueNumber(_ s: String) -> Int? {
        if let n = Int(s.hasPrefix("#") ? String(s.dropFirst()) : s) { return n }
        guard let r = s.range(of: "/issues/") else { return nil }
        return Int(s[r.upperBound...].prefix { $0.isNumber })
    }
}

/// `proof repro`: was the bug there?
public struct ReproReport: Report, Codable {
    public let source: String
    public let flow: FlowRunReport

    public init(source: String, flow: FlowRunReport) { self.source = source; self.flow = flow }

    public var reproduced: Bool { !flow.ok }

    public var text: String {
        var head: String
        if let at = flow.failedAt, let step = flow.steps.first(where: { $0.index == at }) {
            head = "REPRODUCED \(source) · step \(at) \(step.line) — \(step.error ?? "failed")"
        } else if flow.interrupted == true {
            head = "REPRO \(source) · interrupted"
        } else {
            head = "NOT REPRODUCED \(source) · all \(flow.steps.count) steps passed on \(flow.branch) (\(flow.sha))"
        }
        return head + "\n" + flow.text
    }
}

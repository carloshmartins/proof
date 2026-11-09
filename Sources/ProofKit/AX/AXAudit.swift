import Foundation

/// One issue from Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17+).
public struct AuditIssue: Codable, Equatable {
    public struct Element: Codable, Equatable {
        public var type: String
        public var id: String?
        public var label: String?
        public var frame: [Int]?
    }

    public let type: String        // contrast, hit-region, description, dynamic-type, text-clipped, trait, element-detection
    public let summary: String
    public var detail: String?
    public var element: Element?

    var line: String {
        var s = type.padding(toLength: 18, withPad: " ", startingAt: 0)
        if let e = element {
            s += e.type
            if let id = e.id, !id.isEmpty { s += " #\(id)" }
            if let label = e.label, !label.isEmpty { s += " \"\(label)\"" }
            s += "  "
        }
        return s + summary
    }
}

/// `proof ax audit`: Xcode's audit of the current screen plus the interactive elements without identifiers.
public struct AXAuditReport: Report {
    public let supported: Bool          // false on simulators older than iOS 17
    public let issues: [AuditIssue]
    public let missingIdentifiers: [UINode]

    public init(supported: Bool, issues: [AuditIssue], missingIdentifiers: [UINode]) {
        self.supported = supported; self.issues = issues; self.missingIdentifiers = missingIdentifiers
    }

    public var clean: Bool { issues.isEmpty && missingIdentifiers.isEmpty }

    public var text: String {
        var head = "AX AUDIT"
        if clean { head += " clean" }
        if !issues.isEmpty { head += " · \(issues.count) issue\(issues.count == 1 ? "" : "s")" }
        if !missingIdentifiers.isEmpty { head += " · \(missingIdentifiers.count) without identifier" }
        var out = [head]
        out += issues.map(\.line)
        if !missingIdentifiers.isEmpty {
            out.append("without identifier:")
            out.append(UITree.render(missingIdentifiers, interactiveOnly: true))
        }
        if !supported { out.append("(Xcode's audit needs an iOS 17 or newer simulator; only identifiers were checked)") }
        return out.joined(separator: "\n")
    }

    /// Reads the runner's /audit response.
    public static func decodeIssues(_ response: [String: Any]) -> (supported: Bool, issues: [AuditIssue]) {
        let supported = response["supported"] as? Bool ?? false
        let raw = response["issues"] as? [[String: Any]] ?? []
        let issues = raw.compactMap { d -> AuditIssue? in
            guard let type = d["type"] as? String, let summary = d["summary"] as? String else { return nil }
            var issue = AuditIssue(type: type, summary: summary, detail: d["detail"] as? String)
            if let e = d["element"] as? [String: Any], let t = e["type"] as? String {
                issue.element = .init(type: t, id: e["id"] as? String, label: e["label"] as? String, frame: e["frame"] as? [Int])
            }
            return issue
        }
        return (supported, issues)
    }
}

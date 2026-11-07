import Foundation

public struct PacketReport: Report {
    public let markdown: String
    public let html: String
    public let summary: String
    public var text: String { "\(summary)\n\(markdown)" }
}

/// Collects whatever this branch's session produced (build, tests, stack, ax scan, snaps)
/// into report.md and report.html. Nothing is posted anywhere.
public enum Packet {
    public static func build(_ ctx: Context) throws -> PacketReport {
        let dir = ctx.sessionDir
        try Paths.ensureDir(dir)
        let sha = (try? Git.shortSHA(cwd: ctx.root)) ?? "?"
        let build = Session.loadResult("build", sessionDir: dir)
        let test = Session.loadResult("test", sessionDir: dir)
        let stack = Output.readJSON(StackReport.self, from: Paths.join(dir, "results", "stack.json"))
        let ax = Output.readJSON(AXScanReport.self, from: Paths.join(dir, "results", "ax.json"))
        let snaps = Snaps.load(sessionDir: dir).sorted { $0.time < $1.time }

        var md: [String] = ["# Proof · \(ctx.branch) (\(sha))", "", "_\(ctx.repo) · generated \(Date())_", ""]
        var verdict: [String] = []

        func section(_ title: String, _ result: BriefResult?, file: String) {
            guard let r = result else { return }
            md.append("## \(title) \(r.succeeded ? "✅" : "❌")\(ranAt(Paths.join(dir, "results", file)))")
            md.append("```")
            md.append(r.render(maxItems: 30))
            md.append("```")
            verdict.append("\(title.lowercased()) \(r.succeeded ? "ok" : "FAILED")")
        }
        section("Build", build, file: "build.json")
        section("Tests", test, file: "test.json")
        if let stack {
            md.append("## Stack \(stack.ok ? "✅" : "❌")\(ranAt(Paths.join(dir, "results", "stack.json")))")
            md.append("```"); md.append(stack.text); md.append("```")
            verdict.append("stack \(stack.ok ? "ok" : "FAILED")")
        }
        if let ax {
            md.append("## Accessibility identifiers (static) \(ax.findings.isEmpty ? "✅" : "⚠️")")
            md.append("```"); md.append(ax.text); md.append("```")
            verdict.append("ax \(ax.findings.count) missing")
        }

        // Flows: single-branch runs and stack replays.
        let resultFiles = ((try? FileManager.default.contentsOfDirectory(atPath: Paths.join(dir, "results"))) ?? []).sorted()
        for f in resultFiles where f.hasPrefix("flow-stack-") && f.hasSuffix(".json") {
            guard let r = Output.readJSON(StackFlowReport.self, from: Paths.join(dir, "results", f)) else { continue }
            md.append("## Flow \(r.flow) on stack \(r.ok ? "✅" : "❌")\(ranAt(Paths.join(dir, "results", f)))")
            md.append("```"); md.append(r.text); md.append("```")
            verdict.append("flow \(r.flow) stack \(r.ok ? "ok" : "FAILED")")
        }
        for f in resultFiles where f.hasPrefix("flow-") && !f.hasPrefix("flow-stack-") && f.hasSuffix(".json") {
            guard let r = Output.readJSON(FlowRunReport.self, from: Paths.join(dir, "results", f)) else { continue }
            md.append("## Flow \(r.flow) \(r.ok ? "✅" : "❌")\(ranAt(Paths.join(dir, "results", f)))")
            md.append("```"); md.append(r.text); md.append("```")
            verdict.append("flow \(r.flow) \(r.ok ? "ok" : "FAILED")")
        }
        let videos = Video.list(sessionDir: dir)
        if !videos.isEmpty {
            md.append("## Videos")
            md.append(contentsOf: videos.map { "- [\(($0 as NSString).lastPathComponent)](videos/\(($0 as NSString).lastPathComponent))" })
        }

        var htmlScreens: [String] = []
        if !snaps.isEmpty {
            md.append("## Screens (\(snaps.count))")
            for s in snaps {
                md.append("### \(s.name)")
                md.append("![\(s.name)](snaps/\(Paths.sanitize(s.name)).png)")
                if s.missingIdentifiers > 0 { md.append("⚠️ \(s.missingIdentifiers) interactive element(s) without identifier") }
                var before: String? = nil
                if let other = s.compareBranch {
                    let otherSnap = Snaps.load(sessionDir: Paths.session(repo: ctx.repo, branch: other)).first { $0.name == s.name }
                    before = otherSnap?.screenshot
                    if let diff = s.diff {
                        md.append(diff.isEmpty ? "No accessibility tree changes vs `\(other)`." : "Tree diff vs `\(other)`:")
                        if !diff.isEmpty { md.append("```diff"); md.append(contentsOf: diff); md.append("```") }
                    }
                }
                if let tree = try? String(contentsOfFile: s.tree, encoding: .utf8) {
                    md.append("<details><summary>accessibility tree</summary>\n\n```\n\(tree)\n```\n</details>")
                }
                htmlScreens.append(htmlScreen(s, before: before))
            }
            verdict.append("\(snaps.count) screen\(snaps.count == 1 ? "" : "s")")
        }
        if verdict.isEmpty {
            md.append("Nothing recorded yet. Run `proof build`, `proof test`, `proof snap <name>`.")
        }

        let markdown = md.joined(separator: "\n")
        let htmlVideos = videos.map { "<section><h3>\(esc(($0 as NSString).lastPathComponent))</h3><video controls width=320 src=\"file://\($0)\"></video></section>" }
        let html = htmlPage(title: "\(ctx.branch) (\(sha))", markdown: markdown, screens: htmlScreens + htmlVideos)
        try markdown.write(toFile: Paths.join(dir, "report.md"), atomically: true, encoding: .utf8)
        try html.write(toFile: Paths.join(dir, "report.html"), atomically: true, encoding: .utf8)
        let summary = "PACKET \(verdict.isEmpty ? "empty" : verdict.joined(separator: " · ")) → \(Paths.join(dir, "report.md"))"
        return PacketReport(markdown: markdown, html: html, summary: summary)
    }

    public static func reset(_ ctx: Context) throws {
        if Paths.exists(ctx.sessionDir) { try FileManager.default.removeItem(atPath: ctx.sessionDir) }
    }

    static func ranAt(_ path: String) -> String {
        guard let d = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return " · ran \(f.string(from: d))"
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func htmlScreen(_ s: SnapRecord, before: String?) -> String {
        let after = "<figure><img src=\"file://\(s.screenshot)\"><figcaption>\(esc(s.branch)) · \(esc(s.sha))</figcaption></figure>"
        let beforeFig = before.map { "<figure><img src=\"file://\($0)\"><figcaption>\(esc(s.compareBranch ?? ""))</figcaption></figure>" } ?? ""
        var diff = ""
        if let d = s.diff, !d.isEmpty {
            diff = "<pre class=diff>" + d.map { line in
                let cls = line.hasPrefix("+") ? "add" : line.hasPrefix("-") ? "del" : ""
                return "<span class=\"\(cls)\">\(esc(line))</span>"
            }.joined(separator: "\n") + "</pre>"
        }
        return "<section><h3>\(esc(s.name))</h3><div class=pair>\(beforeFig)\(after)</div>\(diff)</section>"
    }

    static func htmlPage(title: String, markdown: String, screens: [String]) -> String {
        // Text sections stay as preformatted markdown; screens get a visual layout.
        let textPart = markdown.components(separatedBy: "\n## Screens").first ?? markdown
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>proof · \(esc(title))</title>
        <style>
        body{font:14px -apple-system,system-ui,sans-serif;margin:24px;color:#1d1d1f;background:#fafafa}
        pre{background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:12px;overflow:auto;font:12px ui-monospace,Menlo,monospace}
        .pair{display:flex;gap:16px;flex-wrap:wrap}
        figure{margin:0}img{width:280px;border-radius:16px;border:1px solid #ddd}
        figcaption{color:#666;font-size:12px;text-align:center;margin-top:4px}
        .add{color:#1a7f37}.del{color:#cf222e}
        @media (prefers-color-scheme: dark){body{background:#1c1c1e;color:#f2f2f7}pre{background:#2c2c2e;border-color:#3a3a3c}}
        </style></head><body>
        <pre>\(esc(textPart))</pre>
        \(screens.joined(separator: "\n"))
        </body></html>
        """
    }
}

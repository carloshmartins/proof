import Foundation

/// Token-lean PR feedback for agents: unresolved review threads, review summaries and
/// conversation comments in one `gh api graphql` call.
public struct PRComments {
    struct Response: Decodable {
        struct DataNode: Decodable { let repository: Repo }
        struct Repo: Decodable { let pullRequest: PR? }
        let data: DataNode
    }
    struct Author: Decodable { let login: String }
    struct PR: Decodable {
        let number: Int
        let title: String
        let url: String
        let reviewThreads: Nodes<Thread>
        let reviews: Nodes<Review>
        let comments: Nodes<Comment>
    }
    struct Nodes<T: Decodable>: Decodable { let nodes: [T] }
    struct Thread: Decodable {
        let isResolved: Bool
        let isOutdated: Bool
        let path: String?
        let line: Int?
        let originalLine: Int?
        let comments: Nodes<Comment>
    }
    struct Review: Decodable { let author: Author?; let state: String; let body: String }
    struct Comment: Decodable { let author: Author?; let body: String }

    public static let query = """
    query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
    number title url
    reviewThreads(first:100){nodes{isResolved isOutdated path line originalLine comments(first:50){nodes{author{login} body}}}}
    reviews(first:100){nodes{author{login} state body}}
    comments(first:100){nodes{author{login} body}}
    }}}
    """

    public struct Options {
        public var includeResolved = false
        public var includeBots = true
        public var maxBody = 600         // 0 = unlimited
        public init() {}
    }

    public static func fetch(number: Int?, cwd: String) throws -> String {
        let repo = try Shell.checked(["gh", "repo", "view", "--json", "owner,name", "-q", ".owner.login + \"/\" + .name"], cwd: cwd)
        let parts = repo.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw ProofError.message("could not resolve GitHub repo") }
        let pr: Int
        if let number { pr = number }
        else {
            let n = try Shell.checked(["gh", "pr", "view", "--json", "number", "-q", ".number"], cwd: cwd)
            guard let parsed = Int(n) else { throw ProofError.message("no PR for the current branch. Pass a number") }
            pr = parsed
        }
        return try Shell.checked(["gh", "api", "graphql", "-f", "query=\(query)",
                                  "-f", "owner=\(parts[0])", "-f", "name=\(parts[1])", "-F", "number=\(pr)"], cwd: cwd)
    }

    public static func report(fromJSON json: String, options: Options) throws -> PRCommentsReport {
        let response = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        guard let pr = response.data.repository.pullRequest else { throw ProofError.message("PR not found") }

        func keep(_ a: Author?) -> Bool { options.includeBots || !isBot(a?.login) }
        func body(_ s: String) -> String { clean(s, max: options.maxBody) }

        var threads: [PRCommentsReport.ThreadItem] = []
        var resolvedCount = 0
        for t in pr.reviewThreads.nodes {
            if t.isResolved { resolvedCount += 1 }
            if t.isResolved && !options.includeResolved { continue }
            let comments = t.comments.nodes.filter { keep($0.author) }
                .map { PRCommentsReport.Entry(author: $0.author?.login ?? "ghost", body: body($0.body)) }
                .filter { !$0.body.isEmpty }
            guard !comments.isEmpty else { continue }
            threads.append(.init(path: t.path, line: t.line ?? t.originalLine, outdated: t.isOutdated, resolved: t.isResolved, comments: comments))
        }
        let reviews = pr.reviews.nodes.filter { keep($0.author) }.compactMap { r -> PRCommentsReport.ReviewItem? in
            let b = body(r.body)
            if b.isEmpty && r.state == "COMMENTED" { return nil }
            return .init(author: r.author?.login ?? "ghost", state: r.state, body: b.isEmpty ? nil : b)
        }
        let comments = pr.comments.nodes.filter { keep($0.author) }
            .map { PRCommentsReport.Entry(author: $0.author?.login ?? "ghost", body: body($0.body)) }
            .filter { !$0.body.isEmpty }
        return PRCommentsReport(number: pr.number, title: pr.title, url: pr.url, threads: threads,
                                resolvedHidden: options.includeResolved ? 0 : resolvedCount, reviews: reviews, comments: comments)
    }

    static func isBot(_ login: String?) -> Bool {
        guard let l = login?.lowercased() else { return false }
        return l.hasSuffix("[bot]") || l.hasSuffix("-bot") || l == "github-actions"
    }

    /// Strips HTML comments and <details> noise, collapses blank lines, truncates.
    static func clean(_ s: String, max: Int) -> String {
        var t = s.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<details>[\s\S]*?</details>"#, with: "[details omitted]", options: .regularExpression)
        t = t.replacingOccurrences(of: "\r", with: "")
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if max > 0, t.count > max { t = String(t.prefix(max)) + " …[truncated]" }
        return t
    }
}

public struct PRCommentsReport: Report {
    public struct Entry: Codable { public let author: String; public let body: String }
    public struct ThreadItem: Codable {
        public let path: String?
        public let line: Int?
        public let outdated: Bool
        public let resolved: Bool
        public let comments: [Entry]
    }
    public struct ReviewItem: Codable { public let author: String; public let state: String; public let body: String? }

    public let number: Int
    public let title: String
    public let url: String
    public let threads: [ThreadItem]
    public let resolvedHidden: Int
    public let reviews: [ReviewItem]
    public let comments: [Entry]

    public var text: String {
        var out = ["PR #\(number) \"\(title)\" · \(threads.count) thread\(threads.count == 1 ? "" : "s")"
                   + (resolvedHidden > 0 ? " (\(resolvedHidden) resolved hidden)" : "")
                   + " · \(reviews.count) review\(reviews.count == 1 ? "" : "s") · \(comments.count) comment\(comments.count == 1 ? "" : "s")"]
        for (i, t) in threads.enumerated() {
            var head = "[\(i + 1)] \(t.path ?? "(general)")\(t.line.map { ":\($0)" } ?? "")"
            if t.outdated { head += " (outdated)" }
            if t.resolved { head += " (resolved)" }
            out.append(head)
            for (j, c) in t.comments.enumerated() {
                let prefix = j == 0 ? "    @\(c.author): " : "    ↳ @\(c.author): "
                out.append(prefix + indent(c.body))
            }
        }
        for r in reviews {
            out.append("REVIEW @\(r.author) \(r.state)" + (r.body.map { ": " + indent($0) } ?? ""))
        }
        for c in comments { out.append("COMMENT @\(c.author): " + indent(c.body)) }
        return out.joined(separator: "\n")
    }

    private func indent(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\n      ") }
}

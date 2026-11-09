import Foundation

/// Test results from the `.xcresult` bundle xcodebuild writes, read with `xcresulttool` (Xcode 16+).
/// More exact than the text log: every failure message whole, the test that crashed, and the attachments
/// a failing test added (UI test screenshots, logs). When it can't be read, the text log's results stand.
public enum XCResult {
    public struct Failure: Equatable {
        public var file: String?
        public var line: Int?
        public var message: String
    }

    public struct TestCase: Equatable {
        public let name: String        // "FlakyTests/testAlwaysFails"
        public let result: String      // Passed, Failed, Skipped, Expected Failure
        public var failures: [Failure]
    }

    /// The bundle for an action in a session: one per action, replaced by every run.
    public static func bundlePath(sessionDir: String, action: String) -> String {
        Paths.join(sessionDir, "results", "\(action).xcresult")
    }

    /// Test cases from `xcresulttool get test-results tests` JSON.
    public static func parseTests(json: String) -> [TestCase] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
        var cases: [TestCase] = []
        func walk(_ node: [String: Any]) {
            let children = node["children"] as? [[String: Any]] ?? []
            if node["nodeType"] as? String == "Test Case" {
                let id = node["nodeIdentifier"] as? String ?? node["name"] as? String ?? "?"
                let failures = children.filter { $0["nodeType"] as? String == "Failure Message" }
                    .compactMap { ($0["name"] as? String).map(parseFailure) }
                cases.append(TestCase(name: normalize(id), result: node["result"] as? String ?? "?", failures: failures))
                return
            }
            children.forEach(walk)
        }
        (root["testNodes"] as? [[String: Any]] ?? []).forEach(walk)
        return cases
    }

    /// "FlakyTests.swift:4: XCTAssertEqual failed: …" → file, line, message.
    static func parseFailure(_ text: String) -> Failure {
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3, parts[0].contains("."), !parts[0].contains(" "), let line = Int(parts[1]) {
            return Failure(file: String(parts[0]), line: line, message: parts[2].trimmingCharacters(in: .whitespaces))
        }
        return Failure(file: nil, line: nil, message: text)
    }

    /// XCTest ids end in "()" in xcresult ("Suite/testX()") but not in the log; Swift Testing keeps them in both.
    static func normalize(_ id: String) -> String {
        guard id.hasSuffix("()"), let slash = id.lastIndex(of: "/") else { return id }
        let method = id[id.index(after: slash)...]
        return method.hasPrefix("test") ? String(id.dropLast(2)) : id
    }

    /// Attachment files per test, from the `manifest.json` of `xcresulttool export attachments`: the exported
    /// file and the readable name to give it ("notes_0_<uuid>.txt" instead of "<uuid>.txt").
    public static func parseManifest(json: String) -> [String: [(exported: String, name: String)]] {
        guard let entries = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return [:] }
        var out: [String: [(exported: String, name: String)]] = [:]
        for e in entries {
            guard let id = e["testIdentifier"] as? String else { continue }
            for a in e["attachments"] as? [[String: Any]] ?? [] {
                guard let file = a["exportedFileName"] as? String else { continue }
                let name = (a["suggestedHumanReadableName"] as? String).map(Paths.sanitize) ?? file
                out[normalize(id), default: []].append((file, name))
            }
        }
        return out
    }

    /// Fills `brief`'s failing tests from the xcresult: exact messages, failures the log missed, attachments.
    public static func apply(_ cases: [TestCase], attachments: [String: [String]], to brief: inout BriefResult) {
        guard !cases.isEmpty else { return }
        var tests = brief.tests ?? TestSummary()
        let flaky = Set(tests.flaky?.map(\.test) ?? [])
        for c in cases where c.result == "Failed" && !flaky.contains(c.name) {
            let first = c.failures.first
            if let i = tests.failures.firstIndex(where: { $0.test == c.name }) {
                if let first {
                    tests.failures[i].message = first.message
                    if tests.failures[i].line == nil { tests.failures[i].line = first.line }
                    if tests.failures[i].file == nil { tests.failures[i].file = first.file }
                }
                tests.failures[i].attachments = attachments[c.name]
            } else {
                var f = TestFailure(test: c.name)
                f.file = first?.file; f.line = first?.line; f.message = first?.message
                f.attachments = attachments[c.name]
                tests.failures.append(f)
                tests.failed += 1
            }
        }
        if brief.tests == nil {
            tests.passed = cases.filter { $0.result == "Passed" }.count
            tests.skipped = cases.filter { $0.result == "Skipped" }.count
        }
        brief.tests = tests
        if tests.failed > 0 { brief.status = "failed" }
    }

    /// Reads the bundle after a test run and applies it. Attachments are exported next to the bundle when a
    /// test failed, and listed for the failing tests. Never throws: without xcresulttool support nothing changes.
    public static func read(_ path: String, into brief: inout BriefResult) {
        guard Paths.exists(path),
              let r = try? Shell.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path]), r.ok else { return }
        let cases = parseTests(json: r.stdout)
        var attachments: [String: [String]] = [:]
        if cases.contains(where: { $0.result == "Failed" }) {
            let dir = path.replacingOccurrences(of: ".xcresult", with: "-attachments")
            try? FileManager.default.removeItem(atPath: dir)
            try? Paths.ensureDir(dir)
            if let e = try? Shell.run(["xcrun", "xcresulttool", "export", "attachments", "--path", path,
                                       "--output-path", dir]), e.ok,
               let manifest = try? String(contentsOfFile: Paths.join(dir, "manifest.json"), encoding: .utf8) {
                for (test, files) in parseManifest(json: manifest) {
                    attachments[test] = files.map { f in
                        let target = Paths.join(dir, f.name)
                        let moved = (try? FileManager.default.moveItem(atPath: Paths.join(dir, f.exported), toPath: target)) != nil
                        return moved ? target : Paths.join(dir, f.exported)
                    }
                }
            }
        }
        apply(cases, attachments: attachments, to: &brief)
        brief.xcresult = path
    }
}

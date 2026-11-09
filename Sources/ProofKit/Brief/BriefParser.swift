import Foundation

public struct Diagnostic: Codable, Hashable {
    public let kind: String          // "error" | "warning"
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let message: String
}

public struct TestFailure: Codable, Hashable {
    public let test: String          // "Class/testName"
    public var file: String?
    public var line: Int?
    public var message: String?
    public var attachments: [String]? = nil   // files the test attached (from the .xcresult)
}

/// A test that failed and then passed when retried (`proof test --retry`).
public struct FlakyTest: Codable, Equatable {
    public let test: String
    public let failedRuns: Int
    public let runs: Int
    public var file: String?
    public var line: Int?
    public var message: String?   // the first failure
}

public struct TestSummary: Codable, Equatable {
    public var passed = 0                     // flaky tests count as passed
    public var failed = 0
    public var skipped = 0
    public var failures: [TestFailure] = []
    public var flaky: [FlakyTest]? = nil      // only when some test needed a retry to pass
    public var total: Int { passed + failed + skipped }
}

public struct BriefResult: Codable, Report {
    public var status: String                 // "succeeded" | "failed" | "unknown"
    public var action: String                 // "build" | "test" | "output"
    public var errors: [Diagnostic] = []
    public var warningCount = 0
    public var warnings: [Diagnostic]? = nil  // only when requested
    public var tests: TestSummary? = nil
    public var duration: Double? = nil
    public var tail: [String]? = nil          // raw tail when failed with nothing recognised
    public var xcresult: String? = nil            // the result bundle the test results were read from
    public var changedCoverage: ChangedCoverage? = nil   // proof test --coverage
    public var newWarnings: [Diagnostic]? = nil   // warnings this branch adds compared with `warningsBase`
    public var warningsBase: String? = nil

    public var succeeded: Bool { status == "succeeded" }

    public var text: String { render(maxItems: 20) }

    public func render(maxItems: Int) -> String {
        var out: [String] = []
        var head = "\(action.uppercased()) \(status.uppercased())"
        if !errors.isEmpty { head += " · \(errors.count) error\(errors.count == 1 ? "" : "s")" }
        if warningCount > 0 { head += " · \(warningCount) warning\(warningCount == 1 ? "" : "s")" }
        if let added = newWarnings, let base = warningsBase {
            head += added.isEmpty ? " · no new warnings vs \(base)" : " · \(added.count) new vs \(base)"
        }
        if let d = duration { head += String(format: " · %.1fs", d) }
        out.append(head)

        for e in errors.prefix(maxItems) { out.append("error  \(Self.location(e.file, e.line, e.column))\(e.message)") }
        if errors.count > maxItems { out.append("… +\(errors.count - maxItems) more errors") }
        if warnings == nil, let added = newWarnings {
            for w in added.prefix(maxItems) { out.append("new    \(Self.location(w.file, w.line, w.column))\(w.message)") }
            if added.count > maxItems { out.append("… +\(added.count - maxItems) more new warnings") }
        }
        if let warnings {
            for w in warnings.prefix(maxItems) { out.append("warn   \(Self.location(w.file, w.line, w.column))\(w.message)") }
            if warnings.count > maxItems { out.append("… +\(warnings.count - maxItems) more warnings") }
        }
        if let t = tests {
            var line = "TESTS \(t.passed) passed · \(t.failed) failed"
            if t.skipped > 0 { line += " · \(t.skipped) skipped" }
            if let flaky = t.flaky, !flaky.isEmpty { line += " · \(flaky.count) flaky" }
            out.append(line)
            for f in t.flaky?.prefix(maxItems) ?? [] {
                var s = "FLAKY  \(f.test)  failed \(f.failedRuns) of \(f.runs) runs"
                if let file = f.file { s += "  \((file as NSString).lastPathComponent)\(f.line.map { ":\($0)" } ?? "")" }
                if let m = f.message { s += "  \(m)" }
                out.append(s)
            }
            for f in t.failures.prefix(maxItems) {
                var s = "FAIL   \(f.test)"
                if let file = f.file { s += "  \((file as NSString).lastPathComponent)\(f.line.map { ":\($0)" } ?? "")" }
                if let m = f.message { s += "  \(m)" }
                out.append(s)
                for a in f.attachments?.prefix(3) ?? [] { out.append("       attachment → \((a as NSString).abbreviatingWithTildeInPath)") }
            }
            if t.failures.count > maxItems { out.append("… +\(t.failures.count - maxItems) more failures") }
        }
        if let changedCoverage { out.append(changedCoverage.text) }
        if let tail { out.append("--- last output ---"); out.append(contentsOf: tail) }
        return out.joined(separator: "\n")
    }

    static func location(_ file: String?, _ line: Int?, _ col: Int?) -> String {
        guard let file else { return "" }
        var s = file
        if let line { s += ":\(line)" }
        if let col { s += ":\(col)" }
        return s + "  "
    }
}

/// Condenses xcodebuild output into what an agent needs: status, deduplicated errors,
/// warning count, test results and failure messages. Handles XCTest and Swift Testing.
public struct BriefParser {
    public var root: String?
    public var keepWarnings = false

    public init(root: String? = nil, keepWarnings: Bool = false) {
        self.root = root
        self.keepWarnings = keepWarnings
    }

    // file:line:col: kind: message
    private static let diagFull = try! NSRegularExpression(pattern: #"^(/[^:]+|[^\s:][^:]*\.[A-Za-z0-9]+):(\d+):(\d+): (error|warning|fatal error): (.*)$"#)
    // file:line: kind: message   (XCTest failure format)
    private static let diagLine = try! NSRegularExpression(pattern: #"^(/[^:]+|[^\s:][^:]*\.[A-Za-z0-9]+):(\d+): (error|warning): (.*)$"#)
    private static let testCase = try! NSRegularExpression(pattern: #"^Test [Cc]ase '(.+?)' (passed|failed|skipped)"#)
    // Swift Testing: "✔ Test foo() passed after…" / "✘ Test "Name" failed after…"
    private static let swiftTest = try! NSRegularExpression(pattern: #"^\W*\s*Test (.+?) (passed|failed|skipped)(?: after| because|\.|$)"#)
    private static let swiftIssue = try! NSRegularExpression(pattern: #"^\W*\s*Test (.+?) recorded an issue at ([^:]+):(\d+):(\d+): (.*)$"#)
    private static let undefinedSymbol = try! NSRegularExpression(pattern: #"^\s+"(.+)", referenced from:"#)
    private static let xcResultDuration = try! NSRegularExpression(pattern: #"Executed \d+ tests?, with \d+ failures? .* in [\d.]+ \(([\d.]+)\) seconds"#)

    /// xcodebuild's "Unable to find a destination" error ends in a colon and lists the destinations on the
    /// following lines. Rewrites it as one line that says which platforms the scheme does build for.
    static func destinationError(_ output: String) -> String {
        var platforms: [String] = []
        var inAvailable = false
        for line in output.split(separator: "\n") {
            if line.contains("Available destinations for") { inAvailable = true; continue }
            guard inAvailable else { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("{"), let r = t.range(of: "platform:") else { if !t.isEmpty { inAvailable = false }; continue }
            let platform = t[r.upperBound...].prefix { $0 != "," && $0 != "}" }.trimmingCharacters(in: .whitespaces)
            if !platforms.contains(platform) { platforms.append(platform) }
        }
        let scheme = output.range(of: #"-scheme ("[^"]+"|\S+)"#, options: .regularExpression)
            .map { output[$0].dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        let name = scheme.map { "scheme \($0)" } ?? "the scheme"
        if platforms.isEmpty || platforms.contains("iOS Simulator") {
            return "the simulator isn't available for \(name). Pick an installed one: proof init --simulator <name>"
        }
        return "\(name) doesn't build for the iOS Simulator (only \(platforms.joined(separator: ", "))). "
            + "Use the iOS app scheme: proof init --scheme <name>"
    }

    public func parse(_ output: String, action: String = "output", duration: Double? = nil) -> BriefResult {
        var result = BriefResult(status: "unknown", action: action)
        var errors: [Diagnostic] = []
        var seenErrors = Set<Diagnostic>()
        var warnings: [Diagnostic] = []
        var seenWarnings = Set<Diagnostic>()
        var tests = TestSummary()
        var sawTests = false
        var testStatus: [String: String] = [:]   // test -> passed/failed/skipped (last wins; retries)
        var testOrder: [String] = []
        var failureInfo: [String: TestFailure] = [:]
        var runs: [String: (failed: Int, total: Int)] = [:]   // per test, over retries
        var undefinedSymbols: [String] = []
        var inUndefined = false
        var statusMarker: String?
        var parsedDuration: Double?

        func add(_ d: Diagnostic) {
            if d.kind == "warning" {
                if seenWarnings.insert(d).inserted { warnings.append(d) }
            } else if seenErrors.insert(d).inserted {
                errors.append(d)
            }
        }
        func setTest(_ name: String, _ status: String, countRun: Bool = true) {
            sawTests = true
            if testStatus[name] == nil { testOrder.append(name) }
            testStatus[name] = status
            if countRun && status != "skipped" {
                let r = runs[name] ?? (0, 0)
                runs[name] = (r.failed + (status == "failed" ? 1 : 0), r.total + 1)
            }
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("** ") && trimmed.hasSuffix(" **") {
                if trimmed.contains("FAILED") { statusMarker = "failed" }
                else if trimmed.contains("SUCCEEDED") && statusMarker != "failed" { statusMarker = "succeeded" }
                continue
            }

            if let m = Self.match(Self.xcResultDuration, line) { parsedDuration = Double(m[1]) }

            // Linker: "Undefined symbols for architecture arm64:" followed by quoted symbols
            if trimmed.hasPrefix("Undefined symbols for architecture") { inUndefined = true; continue }
            if inUndefined {
                if let m = Self.match(Self.undefinedSymbol, line) { undefinedSymbols.append(m[1]); continue }
                if trimmed.hasPrefix("ld:") || trimmed.hasPrefix("clang") || trimmed.isEmpty { inUndefined = false }
                else { continue }
            }

            if let m = Self.match(Self.swiftIssue, trimmed) {
                let name = Self.normalizeTest(m[1])
                var f = failureInfo[name] ?? TestFailure(test: name)
                if f.message == nil { f.file = rel(m[2]); f.line = Int(m[3]); f.message = Self.clean(m[5]) }
                failureInfo[name] = f
                continue
            }
            if let m = Self.match(Self.testCase, trimmed) {
                setTest(Self.normalizeTest(m[1]), m[2]); continue
            }
            let core = trimmed.drop(while: { !$0.isLetter })
            if let m = Self.match(Self.swiftTest, trimmed), !core.hasPrefix("Test Suite"), !core.hasPrefix("Test run") {
                setTest(Self.normalizeTest(m[1]), m[2]); continue
            }

            if let m = Self.match(Self.diagFull, trimmed) {
                let kind = m[4] == "warning" ? "warning" : "error"
                add(Diagnostic(kind: kind, file: rel(m[1]), line: Int(m[2]), column: Int(m[3]), message: Self.clean(m[5])))
                continue
            }
            if let m = Self.match(Self.diagLine, trimmed) {
                let message = m[4]
                if let (test, msg) = Self.splitXCTestFailure(message) {
                    var f = failureInfo[test] ?? TestFailure(test: test)
                    if f.message == nil { f.file = rel(m[1]); f.line = Int(m[2]); f.message = Self.clean(msg) }
                    failureInfo[test] = f
                    if testStatus[test] == nil { setTest(test, "failed", countRun: false) }   // its "failed" line counts the run
                } else {
                    add(Diagnostic(kind: m[3], file: rel(m[1]), line: Int(m[2]), column: nil, message: Self.clean(message)))
                }
                continue
            }
            if trimmed.hasPrefix("error: ") || trimmed.hasPrefix("xcodebuild: error: ") || trimmed.hasPrefix("fatal error: ") {
                var msg = trimmed.components(separatedBy: "error: ").dropFirst().joined(separator: "error: ")
                if msg.hasPrefix("Unable to find a destination matching") { msg = Self.destinationError(output) }
                add(Diagnostic(kind: "error", file: nil, line: nil, column: nil, message: Self.clean(msg)))
                continue
            }
            if trimmed.hasPrefix("ld: ") && !trimmed.hasPrefix("ld: warning") {
                add(Diagnostic(kind: "error", file: nil, line: nil, column: nil, message: trimmed))
                continue
            }
            if trimmed.hasPrefix("warning: ") {
                add(Diagnostic(kind: "warning", file: nil, line: nil, column: nil, message: Self.clean(String(trimmed.dropFirst(9)))))
            }
        }

        if !undefinedSymbols.isEmpty {
            let shown = undefinedSymbols.prefix(10).joined(separator: ", ")
            add(Diagnostic(kind: "error", file: nil, line: nil, column: nil,
                           message: "undefined symbols: \(shown)\(undefinedSymbols.count > 10 ? " …" : "")"))
        }

        if sawTests {
            for name in testOrder {
                switch testStatus[name] {
                case "passed":
                    tests.passed += 1
                    if let r = runs[name], r.failed > 0 {
                        let info = failureInfo[name]
                        tests.flaky = (tests.flaky ?? []) + [FlakyTest(test: name, failedRuns: r.failed, runs: r.total,
                                                                       file: info?.file, line: info?.line, message: info?.message)]
                    }
                case "skipped": tests.skipped += 1
                default:
                    tests.failed += 1
                    tests.failures.append(failureInfo[name] ?? TestFailure(test: name))
                }
            }
            result.tests = tests
        }

        result.errors = errors
        result.warningCount = warnings.count
        if keepWarnings { result.warnings = warnings }
        result.duration = duration ?? parsedDuration

        if let s = statusMarker { result.status = s }
        else if !errors.isEmpty || tests.failed > 0 { result.status = "failed" }
        else if sawTests { result.status = "succeeded" }
        if result.status == "failed" && errors.isEmpty && tests.failed == 0 {
            result.tail = output.split(separator: "\n").suffix(20).map(String.init)
        }
        return result
    }

    private func rel(_ path: String) -> String { Paths.relative(path, to: root) }

    static func match(_ re: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// "-[MyTests.LoginTests testFoo] : XCTAssertEqual failed…" -> ("LoginTests/testFoo", "XCTAssertEqual failed…")
    /// "LoginTests.testFoo() : …" also handled.
    static func splitXCTestFailure(_ message: String) -> (String, String)? {
        guard let sep = message.range(of: " : ") else { return nil }
        let head = String(message[..<sep.lowerBound])
        guard head.hasPrefix("-[") || head.hasSuffix("()") else { return nil }
        return (normalizeTest(head), String(message[sep.upperBound...]))
    }

    /// Normalises test identifiers to "Class/test" across XCTest, parallel XCTest and Swift Testing.
    static func normalizeTest(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("-[") && s.hasSuffix("]") {
            s = String(s.dropFirst(2).dropLast())
            let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
            let cls = parts[0].split(separator: ".").last.map(String.init) ?? parts[0]
            return parts.count > 1 ? "\(cls)/\(parts[1])" : cls
        }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 { return String(s.dropFirst().dropLast()) }
        if s.hasSuffix("()") {
            let comps = s.dropLast(2).split(separator: ".").map(String.init)
            if comps.count >= 2 { return "\(comps[comps.count - 2])/\(comps[comps.count - 1])" }
            return s   // free Swift Testing function: keep "name()"
        }
        return s
    }

    /// Removes the noise xcodebuild adds: trailing "(in target 'X' from project 'Y')".
    static func clean(_ m: String) -> String {
        var s = m
        if let r = s.range(of: #" \(in target '[^']*' from project '[^']*'\)$"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

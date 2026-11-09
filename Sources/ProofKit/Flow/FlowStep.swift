import Foundation

/// One line of a .flow file, e.g. `tap --id login.submit` or `type "me@x.com" --id login.email --clear`.
/// The syntax is exactly `proof ui …` without the prefix, so recorded commands, hand-written flows and
/// agent-written flows are the same thing.
public struct FlowStep: Equatable, Codable {
    public struct Option: Equatable, Codable {
        public let name: String
        public let value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public var action: String
    public var positional: [String] = []
    public var options: [Option] = []
    public var flags: [String] = []
    public var sourceLine: Int? = nil

    public init(action: String, positional: [String] = [], options: [Option] = [], flags: [String] = []) {
        self.action = action; self.positional = positional; self.options = options; self.flags = flags
    }

    public static let actions: Set<String> = [
        "launch", "attach", "terminate", "home", "tap", "longpress", "type", "swipe", "wait",
        "alert", "expect", "snap", "sleep", "include", "open", "push", "permission", "location",
    ]

    /// Steps that change simulator state with simctl instead of going through the runner.
    public static let simulatorActions: Set<String> = ["open", "push", "permission", "location"]

    public func option(_ name: String) -> String? { options.last(where: { $0.name == name })?.value }
    public func all(_ name: String) -> [String] { options.filter { $0.name == name }.map(\.value) }
    public func flag(_ name: String) -> Bool { flags.contains(name) }

    // MARK: - Parsing

    /// Parses tokens (already split). `--name value` is an option, `--name` followed by another
    /// `--…` or the end is a flag.
    public static func parse(tokens: [String], line: Int? = nil) throws -> FlowStep {
        guard let action = tokens.first else { throw ProofError.message("empty step") }
        guard actions.contains(action) else {
            throw ProofError.message("line \(line.map(String.init) ?? "?"): unknown step '\(action)'. Known: \(actions.sorted().joined(separator: ", "))")
        }
        var step = FlowStep(action: action)
        step.sourceLine = line
        var i = 1
        while i < tokens.count {
            let t = tokens[i]
            if t.hasPrefix("--") && t.count > 2 {
                let name = String(t.dropFirst(2))
                if i + 1 < tokens.count, !tokens[i + 1].hasPrefix("--") {
                    step.options.append(Option(name: name, value: tokens[i + 1]))
                    i += 2
                } else {
                    step.flags.append(name)
                    i += 1
                }
            } else {
                step.positional.append(t)
                i += 1
            }
        }
        return step
    }

    public static func parse(line text: String, line: Int? = nil) throws -> FlowStep? {
        let tokens = try tokenize(text)
        guard !tokens.isEmpty else { return nil }
        return try parse(tokens: tokens, line: line)
    }

    /// Shell-like split: whitespace separated, "double" and 'single' quotes, backslash escapes in
    /// double quotes, `#` starts a comment outside quotes.
    public static func tokenize(_ s: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var quote: Character? = nil
        var escape = false
        for c in s {
            if escape { current.append(c); escape = false; continue }
            if let q = quote {
                if c == "\\" && q == "\"" { escape = true }
                else if c == q { quote = nil }
                else { current.append(c) }
                continue
            }
            if c == "\"" || c == "'" { quote = c; inToken = true; continue }
            if c == "#" && !inToken { break }
            if c == " " || c == "\t" {
                if inToken { tokens.append(current); current = ""; inToken = false }
                continue
            }
            current.append(c); inToken = true
        }
        if quote != nil { throw ProofError.message("unterminated quote in: \(s)") }
        if inToken { tokens.append(current) }
        return tokens
    }

    // MARK: - Serialising

    public var tokens: [String] {
        var t = [action] + positional
        for o in options { t += ["--\(o.name)", o.value] }
        t += flags.map { "--\($0)" }
        return t
    }

    public var line: String { tokens.map(Self.quote).joined(separator: " ") }

    public static func quote(_ s: String) -> String {
        let safe = !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || "-_./:@=,+%$&{}".contains($0) }
        if safe { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Variables

    /// Replaces ${NAME} from `vars`, then the environment. Unknown names are an error,
    /// so a flow never silently types "${PASSWORD}".
    public func substituting(_ vars: [String: String]) throws -> FlowStep {
        func sub(_ s: String) throws -> String {
            guard s.contains("${") else { return s }
            var out = ""
            var rest = Substring(s)
            while let start = rest.range(of: "${") {
                out += rest[..<start.lowerBound]
                guard let end = rest[start.upperBound...].firstIndex(of: "}") else { out += rest[start.lowerBound...]; rest = ""; break }
                let name = String(rest[start.upperBound..<end])
                guard let value = vars[name] ?? ProcessInfo.processInfo.environment[name] else {
                    throw ProofError.message("line \(sourceLine.map(String.init) ?? "?"): undefined variable ${\(name)}. Pass --var \(name)=…")
                }
                out += value
                rest = rest[rest.index(after: end)...]
            }
            return out + rest
        }
        var copy = self
        copy.positional = try positional.map(sub)
        copy.options = try options.map { Option(name: $0.name, value: try sub($0.value)) }
        return copy
    }

    // MARK: - Runner request

    static let selectorKeys = ["id", "label", "text", "type"]

    var selector: [String: Any] {
        var d: [String: Any] = [:]
        for k in Self.selectorKeys { if let v = option(k) { d[k] = v } }
        if let i = option("index"), let n = Int(i) { d["index"] = n }
        return d
    }

    var hasSelector: Bool { Self.selectorKeys.contains { option($0) != nil } }

    /// Runner endpoint and JSON body for runner-backed steps. nil for local steps (snap, sleep, include).
    public func runnerRequest(defaultBundleId: String?) throws -> (path: String, body: [String: Any])? {
        func number(_ name: String) throws -> Double? {
            guard let v = option(name) else { return nil }
            guard let d = Double(v) else { throw ProofError.message("--\(name) must be a number, got \(v)") }
            return d
        }
        switch action {
        case "launch", "attach":
            guard let id = option("bundle-id") ?? defaultBundleId else {
                throw ProofError.message("\(action): no bundle id. Add --bundle-id or run `proof run` once")
            }
            var body: [String: Any] = ["bundleId": id]
            if action == "launch" {
                body["arguments"] = all("arg")
                var env: [String: String] = [:]
                for pair in all("env") {
                    let p = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    if p.count == 2 { env[p[0]] = p[1] }
                }
                body["environment"] = env
            }
            return (action == "launch" ? "/launch" : "/activate", body)
        case "terminate": return ("/terminate", [:])
        case "home": return ("/home", [:])
        case "tap":
            var body = selector
            if let x = try number("x"), let y = try number("y") { body["x"] = x; body["y"] = y }
            else if !hasSelector { throw ProofError.message("tap needs --id/--label/--text/--type or --x and --y") }
            return ("/tap", body)
        case "longpress":
            guard hasSelector else { throw ProofError.message("longpress needs a selector") }
            var body = selector
            let duration: Double = try number("duration") ?? 1
            body["duration"] = duration
            return ("/longpress", body)
        case "type":
            guard let value = positional.first else { throw ProofError.message("type needs the text to type") }
            var body = selector
            body["value"] = value
            body["clear"] = flag("clear")
            body["submit"] = flag("submit")
            return ("/type", body)
        case "swipe":
            var body = selector
            body["direction"] = positional.first ?? option("direction") ?? "up"
            return ("/swipe", body)
        case "wait", "expect":
            guard hasSelector else { throw ProofError.message("\(action) needs a selector") }
            var body = selector
            let timeout: Double = try number("timeout") ?? (action == "expect" ? 5 : 10)
            body["timeout"] = timeout
            body["gone"] = flag("gone")
            return ("/wait", body)
        case "alert":
            var body: [String: Any] = ["action": flag("dismiss") ? "dismiss" : "accept"]
            if let b = option("button") { body["button"] = b }
            if let t = try number("timeout") { body["timeout"] = t }
            return ("/alert", body)
        default:
            return nil
        }
    }
}

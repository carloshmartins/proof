import Foundation

/// Every command result is a Report: compact text for humans, `--json` for agents.
public protocol Report: Encodable {
    var text: String { get }
}

public enum Output {
    /// Where the full text of the last output cut by `--max-lines` is kept.
    public static var lastOutputPath: String { Paths.join(Paths.home, "last-output.txt") }

    /// The line budget: `--max-lines`, else `PROOF_MAX_LINES`, else none.
    public static func lineBudget(_ flag: Int?) -> Int? {
        flag ?? ProcessInfo.processInfo.environment["PROOF_MAX_LINES"].flatMap(Int.init)
    }

    /// Prints a report: JSON whole, text cut to `maxLines` when given (the full text goes to `lastOutputPath`).
    public static func emit<R: Report>(_ report: R, json: Bool, maxLines: Int? = nil) {
        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? enc.encode(report) { print(String(decoding: data, as: UTF8.self)) }
        } else {
            let text = report.text
            let (shown, cut) = budget(text, maxLines: maxLines)
            if cut > 0 {
                try? Paths.ensureDir(Paths.home)
                try? text.write(toFile: lastOutputPath, atomically: true, encoding: .utf8)
            }
            print(cut > 0 ? shown + "\n… +\(cut) lines → \((lastOutputPath as NSString).abbreviatingWithTildeInPath)" : text)
        }
    }

    /// The first `maxLines - 1` lines and how many were cut (the last line says where the rest is).
    /// Reports put the verdict first, so the head is what matters.
    public static func budget(_ text: String, maxLines: Int?) -> (text: String, cut: Int) {
        guard let maxLines, maxLines > 0 else { return (text, 0) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return (text, 0) }
        let keep = max(1, maxLines - 1)
        return (lines.prefix(keep).joined(separator: "\n"), lines.count - keep)
    }

    public static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(value).write(to: URL(fileURLWithPath: path))
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func stderr(_ s: String) {
        // On a terminal, clear a live progress line first so the message doesn't land on its end.
        let clear = isatty(STDERR_FILENO) == 1 ? "\r\u{1B}[2K" : ""
        FileHandle.standardError.write(Data((clear + s + "\n").utf8))
    }
}

/// Small generic report for simple commands.
public struct MessageReport: Report {
    public let ok: Bool
    public let message: String
    public var text: String { message }
    public init(ok: Bool = true, _ message: String) { self.ok = ok; self.message = message }
}

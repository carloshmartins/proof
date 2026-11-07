import Foundation

/// Every command result is a Report: compact text for humans, `--json` for agents.
public protocol Report: Encodable {
    var text: String { get }
}

public enum Output {
    public static func emit<R: Report>(_ report: R, json: Bool) {
        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? enc.encode(report) { print(String(decoding: data, as: UTF8.self)) }
        } else {
            print(report.text)
        }
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
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}

/// Small generic report for simple commands.
public struct MessageReport: Report {
    public let ok: Bool
    public let message: String
    public var text: String { message }
    public init(ok: Bool = true, _ message: String) { self.ok = ok; self.message = message }
}

import Foundation

/// Every result is also archived, so a branch keeps its run history, not only the latest run:
///   <session>/results/history/<yyyyMMdd-HHmmss-SSS>__<kind>__<status>__<name>.json
/// kind: build | test | stack | flow | flow-stack | ax.  status: ok | failed.
/// The file name carries everything a list needs; the JSON is only read when a run is opened.
public enum History {
    public static var keepPerKind = 50

    public struct Entry: Equatable, Hashable {
        public let path: String
        public let time: Date
        public let kind: String
        public let status: String
        public let name: String

        public var ok: Bool { status == "ok" }
    }

    public static func dir(_ sessionDir: String) -> String { Paths.join(sessionDir, "results", "history") }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    /// Best effort: archiving never fails the command.
    public static func archive<T: Encodable>(_ value: T, kind: String, ok: Bool, name: String = "", sessionDir: String, at date: Date = Date()) {
        let d = dir(sessionDir)
        try? Paths.ensureDir(d)
        let file = "\(formatter.string(from: date))__\(kind)__\(ok ? "ok" : "failed")__\(safe(name)).json"
        try? Output.writeJSON(value, to: Paths.join(d, file))
        prune(sessionDir, kind: kind, name: name)
    }

    public static func safe(_ name: String) -> String {
        var s = Paths.sanitize(name)
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        return s
    }

    public static func parse(_ file: String, in dir: String) -> Entry? {
        guard file.hasSuffix(".json") else { return nil }
        let parts = String(file.dropLast(5)).components(separatedBy: "__")
        guard parts.count == 4, let time = formatter.date(from: parts[0]) else { return nil }
        return Entry(path: Paths.join(dir, file), time: time, kind: parts[1], status: parts[2], name: parts[3])
    }

    /// Newest first.
    public static func entries(_ sessionDir: String) -> [Entry] {
        let d = dir(sessionDir)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
        return files.compactMap { parse($0, in: d) }.sorted { $0.time == $1.time ? $0.path > $1.path : $0.time > $1.time }
    }

    static func prune(_ sessionDir: String, kind: String, name: String) {
        let same = entries(sessionDir).filter { $0.kind == kind && $0.name == safe(name) }
        for old in same.dropFirst(keepPerKind) { try? FileManager.default.removeItem(atPath: old.path) }
    }
}

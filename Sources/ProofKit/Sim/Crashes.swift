import Foundation

/// A crash of the app under test, read from the crash report macOS writes for simulator apps
/// (`~/Library/Logs/DiagnosticReports/<App>-<date>.ips`).
public struct CrashReport: Codable, Equatable {
    public struct Frame: Codable, Equatable {
        public let image: String
        public let symbol: String?
        public let file: String?
        public let line: Int?
        public let inApp: Bool

        /// "App.swift:14", when the frame has source info.
        public var location: String? { file.map { f in line.map { "\(f):\($0)" } ?? f } }

        var rendered: String { "\(image)  \(symbol ?? "?")" + (location.map { "  (\($0))" } ?? "") }
    }

    public let app: String
    public let bundleId: String
    public let exception: String      // "EXC_BREAKPOINT (SIGTRAP)"
    public let time: String?
    public let frames: [Frame]        // crashed thread, top first
    public let path: String

    /// The first frame in the app's own code, where to look first.
    public var appFrame: Frame? { frames.first(where: \.inApp) }

    /// Swift traps (fatalError, force unwrap, index out of range, precondition) end in _assertionFailure.
    public var isSwiftTrap: Bool { frames.prefix(6).contains { $0.symbol?.contains("_assertionFailure") == true } }

    /// One line: "app crashed: EXC_BREAKPOINT (SIGTRAP) at App.swift:14".
    public var summary: String {
        "app crashed: \(exception)" + (appFrame.map { " at " + ($0.location ?? $0.symbol ?? $0.image) } ?? "")
    }

    public var text: String {
        var out = ["CRASH \(app) · \(exception)" + (isSwiftTrap ? " · Swift runtime trap" : "")]
        if let f = appFrame { out.append("at " + (f.location ?? f.image) + "  " + (f.symbol ?? "?")) }
        let shown = frames.prefix(max(8, (frames.firstIndex(where: \.inApp) ?? 0) + 3))
        out += shown.enumerated().map { "  \($0.offset) " + ($0.element.inApp ? "▸ " : "  ") + $0.element.rendered }
        out.append("report → \((path as NSString).abbreviatingWithTildeInPath)")
        return out.joined(separator: "\n")
    }
}

public enum Crashes {
    public static var reportsDir: String {
        ProcessInfo.processInfo.environment["PROOF_CRASH_REPORTS"]
            ?? Paths.join(NSHomeDirectory(), "Library/Logs/DiagnosticReports")
    }

    /// Parses an .ips file: one JSON header line, then the JSON report.
    public static func parse(ips text: String, path: String) -> CrashReport? {
        guard let newline = text.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(text[..<newline].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any]
        else { return nil }
        let bundleId = header["bundleID"] as? String ?? (body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String ?? ""
        let app = header["app_name"] as? String ?? body["procName"] as? String ?? "app"
        let exception = body["exception"] as? [String: Any]
        let kind = [exception?["type"] as? String, (exception?["signal"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")

        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
        let rawFrames = faulting < threads.count ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
        let frames = rawFrames.map { f -> CrashReport.Frame in
            let image = (f["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0] : nil }
            let imagePath = image?["path"] as? String ?? ""
            return CrashReport.Frame(
                image: image?["name"] as? String ?? "?",
                symbol: f["symbol"] as? String,
                file: f["sourceFile"] as? String,
                line: f["sourceLine"] as? Int,
                inApp: imagePath.contains(".app/") && !imagePath.contains("/Frameworks/"))
        }
        return CrashReport(app: app, bundleId: bundleId, exception: kind.isEmpty ? "crashed" : kind,
                           time: body["captureTime"] as? String ?? header["timestamp"] as? String,
                           frames: frames, path: path)
    }

    /// Crash reports of `bundleId` written since `since`, newest first.
    public static func find(bundleId: String, since: Date, dir: String = reportsDir) -> [CrashReport] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".ips") && !$0.hasPrefix(".") }
            .compactMap { name -> (Date, String)? in
                let path = Paths.join(dir, name)
                guard let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, date >= since else { return nil }
                return (date, path)
            }
            .sorted { $0.0 > $1.0 }
            .compactMap { _, path in
                guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                      let report = parse(ips: text, path: path), report.bundleId == bundleId else { return nil }
                return report
            }
    }

    /// The newest crash of the app under test since `since` that this session hasn't reported yet, and
    /// marks it reported. When `wait` is set it polls a few seconds: macOS writes the report about a second
    /// after the crash.
    public static func unreported(_ ctx: Context, since: Date, wait: TimeInterval = 0) -> CrashReport? {
        guard let bundleId = ctx.config.bundleId else { return nil }
        let seenPath = Paths.join(ctx.sessionDir, "crashes-seen.json")
        var seen = Set(Output.readJSON([String].self, from: seenPath) ?? [])
        let deadline = Date().addingTimeInterval(wait)
        while true {
            if let crash = find(bundleId: bundleId, since: since).first(where: { !seen.contains($0.path) }) {
                seen.insert(crash.path)
                try? Paths.ensureDir(ctx.sessionDir)
                try? Output.writeJSON(seen.sorted(), to: seenPath)
                return crash
            }
            if Date() >= deadline { return nil }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Whether a runner error means the app is gone, so it's worth waiting for its crash report.
    public static func looksLikeAppGone(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("is not running") || m.contains("not running") || m.contains("terminated") || m.contains("crash")
    }
}

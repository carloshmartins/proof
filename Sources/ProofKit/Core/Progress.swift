import Foundation

/// What xcodebuild is doing, read from its raw output one line at a time.
public struct BuildActivity: Equatable {
    public var step = "starting"
    public var compiled = 0
    public var testsPassed = 0
    public var testsFailed = 0

    public init() {}

    /// Updates the activity from one output line. Lines that say nothing new are ignored.
    public mutating func consume<S: StringProtocol>(_ raw: S) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        if line.hasPrefix("Resolve Package Graph") || line.hasPrefix("Fetching from") || line.hasPrefix("Resolving source packages") {
            step = "resolving packages"
        } else if line.hasPrefix("ComputePackagePrebuildTargetDependencyGraph") || line.hasPrefix("Prepare build")
                    || line.hasPrefix("Build description") || line.hasPrefix("CreateBuildDescription") {
            step = "planning build"
        } else if line.hasPrefix("SwiftCompile ") || line.hasPrefix("CompileSwift ") || line.hasPrefix("CompileC ") {
            compiled += 1
            step = Self.sourceFile(in: line).map { "compiling \($0)" } ?? "compiling"
        } else if line.hasPrefix("CompileAssetCatalog") {
            step = "compiling assets"
        } else if line.hasPrefix("CompileStoryboard") || line.hasPrefix("CompileXIB") || line.hasPrefix("LinkStoryboards") {
            step = "compiling interface files"
        } else if line.hasPrefix("PhaseScriptExecution ") {
            step = "running script " + Self.firstArgument(of: line)
        } else if line.hasPrefix("Ld ") {
            step = "linking " + ((Self.firstArgument(of: line) as NSString).lastPathComponent)
        } else if line.hasPrefix("CodeSign ") {
            step = "signing"
        } else if line.hasPrefix("Testing started") || line.hasPrefix("Test Suite 'All tests' started") || line.hasPrefix("◇ Test run started") {
            step = "running tests"
        } else if line.hasPrefix("Test Case '") {
            let name = Self.xctestName(line)
            if line.contains("' started") { step = "testing \(name)" }
            else if line.contains("' passed") { testsPassed += 1 }
            else if line.contains("' failed") { testsFailed += 1 }
        } else if line.hasPrefix("Test case '") {
            // Parallel testing reports each finished test from its simulator clone.
            if line.contains("' passed on") { testsPassed += 1 }
            else if line.contains("' failed on") { testsFailed += 1 }
            step = "testing " + Self.xctestName(line)
        } else if line.hasPrefix("◇ Test ") && line.hasSuffix(" started.") {
            step = "testing " + line.dropFirst("◇ Test ".count).dropLast(" started.".count)
        } else if line.hasPrefix("✔ Test ") && !line.hasPrefix("✔ Test run") && line.contains(" passed") {
            testsPassed += 1
        } else if line.hasPrefix("✘ Test ") && !line.hasPrefix("✘ Test run") && line.contains(" failed after") {
            testsFailed += 1
        }
    }

    /// One short phrase, e.g. "compiling LoginView.swift · 214 files" or "testing LoginTests.testValid · 12 passed, 1 failed".
    public var summary: String {
        var parts = [step]
        if compiled > 0 && step.hasPrefix("compiling") { parts.append("\(compiled) file\(compiled == 1 ? "" : "s")") }
        if testsPassed + testsFailed > 0 {
            parts.append("\(testsPassed) passed" + (testsFailed > 0 ? ", \(testsFailed) failed" : ""))
        }
        return parts.joined(separator: " · ")
    }

    static func sourceFile(in line: String) -> String? {
        let extensions = [".swift", ".m", ".mm", ".c", ".cc", ".cpp"]
        // The source is the last path in the line; target info "(in target …)" comes after it.
        let head = line.components(separatedBy: " (in target").first ?? line
        let tokens = head.replacingOccurrences(of: "\\ ", with: "\u{0}").split(separator: " ")
        guard let token = tokens.last(where: { t in extensions.contains { t.hasSuffix($0) } }) else { return nil }
        return (String(token).replacingOccurrences(of: "\u{0}", with: " ") as NSString).lastPathComponent
    }

    /// The first argument after the command name, with escaped spaces kept.
    static func firstArgument(of line: String) -> String {
        let tokens = line.replacingOccurrences(of: "\\ ", with: "\u{0}").split(separator: " ")
        guard tokens.count > 1 else { return "" }
        return String(tokens[1]).replacingOccurrences(of: "\u{0}", with: " ")
    }

    /// "-[LoginTests.LoginViewModelTests testValidEmail]" → "LoginViewModelTests.testValidEmail".
    static func xctestName(_ line: String) -> String {
        guard let open = line.firstIndex(of: "'"), let close = line[line.index(after: open)...].firstIndex(of: "'") else { return "" }
        var name = String(line[line.index(after: open)..<close])
        if name.hasPrefix("-[") && name.hasSuffix("]") {
            name = String(name.dropFirst(2).dropLast())
            let parts = name.split(separator: " ")
            if parts.count == 2 { name = "\(parts[0].split(separator: ".").last ?? parts[0]).\(parts[1])" }
        }
        return name
    }
}

/// Tells the person running proof that a long command is still working.
///
/// On a terminal it keeps one live line on stderr: spinner, elapsed time and what xcodebuild is doing.
/// Elsewhere (an agent, CI, a pipe) it prints a start line and a short heartbeat every 15 seconds,
/// so nothing redraws in place. stdout is never touched, so `--json` output stays clean.
public final class ProgressLine {
    public let title: String
    private let interactive: Bool
    private let heartbeat: TimeInterval
    private let start = Date()
    private let lock = NSLock()
    private var activity = BuildActivity()
    private var pending = Data()
    private var timer: DispatchSourceTimer?
    private var frame = 0
    private var lastBeat = Date()
    private var finished = false

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// Off when `PROOF_NO_PROGRESS` is set.
    public static var enabled: Bool { ProcessInfo.processInfo.environment["PROOF_NO_PROGRESS"] == nil }

    public init(_ title: String, detail: String? = nil, interactive: Bool = isatty(STDERR_FILENO) == 1, heartbeat: TimeInterval = 15) {
        self.title = title
        self.interactive = interactive
        self.heartbeat = heartbeat
        guard Self.enabled else { finished = true; return }
        if !interactive || detail != nil {
            Output.stderr(title + "…" + (detail.map { " (\($0))" } ?? ""))
        }
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now(), repeating: interactive ? 0.1 : 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    deinit { finish() }

    /// Feeds raw process output. Safe to call from any thread.
    public func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...newline)
            activity.consume(line)
        }
    }

    var current: BuildActivity { lock.lock(); defer { lock.unlock() }; return activity }

    /// Stops the timer and clears the live line.
    public func finish() {
        lock.lock()
        let wasFinished = finished
        finished = true
        lock.unlock()
        guard !wasFinished else { return }
        timer?.cancel()
        timer = nil
        if interactive { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
    }

    public static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s)s" : String(format: "%dm%02ds", s / 60, s % 60)
    }

    private func tick() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let now = Date()
        let status = "\(title) · \(Self.elapsed(now.timeIntervalSince(start))) · \(activity.summary)"
        if interactive {
            frame = (frame + 1) % Self.frames.count
            let line = Self.truncate("\(Self.frames[frame]) \(status)", to: Self.terminalWidth() - 1)
            FileHandle.standardError.write(Data("\r\u{1B}[2K\(line)".utf8))
        } else if now.timeIntervalSince(lastBeat) >= heartbeat {
            lastBeat = now
            Output.stderr("… " + status)
        }
        lock.unlock()
    }

    static func truncate(_ s: String, to width: Int) -> String {
        guard width > 1, s.count > width else { return s }
        return String(s.prefix(width - 1)) + "…"
    }

    private static func terminalWidth() -> Int {
        var size = winsize()
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
        return 80
    }
}

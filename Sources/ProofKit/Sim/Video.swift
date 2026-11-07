import Foundation

/// Screen recording via `simctl io recordVideo`, stopped with SIGINT so the file is finalised.
public enum Video {
    struct State: Codable { let pid: Int32; let path: String; let session: String }
    static var stateFile: String { Paths.join(Paths.home, "video.json") }

    public static var isRecording: Bool {
        guard let s = Output.readJSON(State.self, from: stateFile) else { return false }
        return Shell.isAlive(s.pid)
    }

    /// Starts recording the simulator the runner is attached to (or the configured one).
    @discardableResult
    public static func start(_ ctx: Context, name: String) throws -> String {
        if isRecording { _ = stop() }
        let udid = try Runner.state()?.udid ?? Simulators.resolveBooted(ctx.config.simulator).udid
        let dir = Paths.join(ctx.sessionDir, "videos")
        try Paths.ensureDir(dir)
        let path = Paths.join(dir, "\(Paths.sanitize(name))-\(Session.timestamp()).mp4")
        let pid = try Shell.spawnDetached(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", path],
                                          log: Paths.join(dir, "recordVideo.log"))
        try Output.writeJSON(State(pid: pid, path: path, session: ctx.sessionDir), to: stateFile)
        Thread.sleep(forTimeInterval: 1)   // recordVideo needs a moment before the first frame
        Events.append(ProofEvent(kind: "video", name: name, status: "started", file: path), ctx: ctx)
        return path
    }

    /// Stops the active recording. Returns the file path once it is written.
    @discardableResult
    public static func stop() -> String? {
        guard let s = Output.readJSON(State.self, from: stateFile) else { return nil }
        try? FileManager.default.removeItem(atPath: stateFile)
        if Shell.isAlive(s.pid) {
            kill(s.pid, SIGINT)
            let deadline = Date().addingTimeInterval(15)
            while Shell.isAlive(s.pid) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        }
        return Paths.exists(s.path) ? s.path : nil
    }

    public static func list(sessionDir: String) -> [String] {
        let dir = Paths.join(sessionDir, "videos")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".mp4") }.sorted().map { Paths.join(dir, $0) }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RunnerState: Codable {
    public let pid: Int32
    public let port: Int
    public let udid: String
    public let sourceStamp: String
}

/// Lifecycle of the standalone XCUITest runner: build once, start in the background,
/// talk to it over localhost, stop on demand.
public enum Runner {
    public static var port: Int { Int(ProcessInfo.processInfo.environment["PROOF_PORT"] ?? "") ?? 22087 }

    static var project: String { Paths.join(Paths.runnerSource, "ProofRunner.xcodeproj") }

    /// Changes whenever the runner sources change, so a reinstall triggers a rebuild.
    static func sourceStamp() -> String {
        let dir = Paths.join(Paths.runnerSource, "ProofRunnerUITests")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var parts: [String] = []
        for f in files.sorted() {
            let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.join(dir, f))
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(f):\(size):\(Int(mod))")
        }
        return parts.joined(separator: "|")
    }

    static func xctestrun() -> String? {
        let products = Paths.join(Paths.runnerDerivedData, "Build", "Products")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: products)) ?? []
        return files.filter { $0.hasSuffix(".xctestrun") && $0.contains("iphonesimulator") }
            .sorted().last.map { Paths.join(products, $0) }
    }

    static var stampFile: String { Paths.join(Paths.runnerDir, "build.stamp") }

    /// Builds the runner if it was never built or its sources changed.
    public static func buildIfNeeded(force: Bool = false) throws {
        if !Paths.exists(project) {
            // A fresh or cleared ~/.proof: install the sources that ship with this binary instead of failing.
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            guard let resources = Installer.resources(executable: exe), resources.isComplete else {
                throw ProofError.message("runner sources missing at \(Paths.runnerSource). Run `proof setup`")
            }
            Output.stderr("installing proof runner sources from \(resources.root)…")
            try Installer.installRunner(resources)
        }
        let stamp = sourceStamp()
        let built = (try? String(contentsOfFile: stampFile, encoding: .utf8)) ?? ""
        if !force, built == stamp, xctestrun() != nil { return }
        Output.stderr("building proof runner (one time, ~1 min)…")
        let r = try Shell.run(["xcodebuild", "build-for-testing", "-project", project, "-scheme", "ProofRunner",
                               "-destination", "generic/platform=iOS Simulator",
                               "-derivedDataPath", Paths.runnerDerivedData])
        guard r.ok else {
            let brief = BriefParser().parse(r.combined, action: "build")
            throw ProofError.message("runner build failed\n" + brief.text)
        }
        try stamp.write(toFile: stampFile, atomically: true, encoding: .utf8)
    }

    public static func state() -> RunnerState? { Output.readJSON(RunnerState.self, from: Paths.runnerState) }

    public static func isHealthy() -> Bool {
        (try? request("/health", [:], timeout: 2))?["ok"] as? Bool == true
    }

    /// Starts the runner on the given simulator if it is not already serving there.
    @discardableResult
    public static func ensureRunning(simulator: String?) throws -> RunnerState {
        let sim = try Simulators.resolveBooted(simulator)
        if let s = state(), s.udid == sim.udid, isHealthy() { return s }
        if state() != nil { stop() }
        try buildIfNeeded()
        guard let xctestrun = xctestrun() else { throw ProofError.message("runner .xctestrun not found after build") }

        let pid = try Shell.spawnDetached(
            ["xcodebuild", "test-without-building", "-xctestrun", xctestrun,
             "-destination", Simulators.destination(sim),
             "-only-testing:ProofRunnerUITests/RunnerTests/testServe"],
            env: ["TEST_RUNNER_PROOF_PORT": String(port)],   // xcodebuild forwards TEST_RUNNER_* to the test process
            log: Paths.runnerLog
        )
        let state = RunnerState(pid: pid, port: port, udid: sim.udid, sourceStamp: sourceStamp())
        try Output.writeJSON(state, to: Paths.runnerState)

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if isHealthy() { startedAt = Date(); return state }
            if !Shell.isAlive(pid) {
                let tail = ((try? String(contentsOfFile: Paths.runnerLog, encoding: .utf8)) ?? "")
                    .split(separator: "\n").suffix(20).joined(separator: "\n")
                throw ProofError.message("runner exited during startup. Log: \(Paths.runnerLog)\n\(tail)")
            }
            Thread.sleep(forTimeInterval: 1)
        }
        throw ProofError.message("runner did not become healthy within 120s. Log: \(Paths.runnerLog)")
    }

    /// When this process started the runner (nil if it found one already serving).
    static var startedAt: Date?

    public static func stop() {
        _ = try? request("/shutdown", [:], timeout: 2)
        if let s = state() {
            Thread.sleep(forTimeInterval: 1)
            if Shell.isAlive(s.pid) { kill(s.pid, SIGTERM) }
        }
        try? FileManager.default.removeItem(atPath: Paths.runnerState)
    }

    /// POSTs a JSON command and returns the decoded response object.
    public static func request(_ path: String, _ body: [String: Any], timeout: TimeInterval = 60) throws -> [String: Any] {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { throw ProofError.message("bad url") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]   // never route localhost through a proxy
        let session = URLSession(configuration: config)
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(ProofError.message("no response"))
        session.dataTask(with: req) { data, _, error in
            if let error { result = .failure(error) } else { result = .success(data ?? Data()) }
            sem.signal()
        }.resume()
        sem.wait()
        let data = try result.get()
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProofError.message("runner returned invalid JSON")
        }
        return obj
    }

    /// Sends a command, starting the runner if needed. Throws on `ok: false`.
    public static func command(_ path: String, _ body: [String: Any], simulator: String?) throws -> [String: Any] {
        try ensureRunning(simulator: simulator)
        let response: [String: Any]
        do {
            response = try request(path, body)
        } catch let error as URLError where startedAt.map({ Date().timeIntervalSince($0) < 15 }) == true
                    && [.networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            // A runner that just answered /health can still drop the first connection while it settles.
            // Only right after a start, so a command is never sent twice to a runner that has been up.
            Thread.sleep(forTimeInterval: 1)
            response = try request(path, body)
        }
        if response["ok"] as? Bool == false {
            throw ProofError.message((response["error"] as? String) ?? "runner command failed")
        }
        return response
    }
}

import Foundation

public struct ShellResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
    /// stdout + stderr, in that order. xcodebuild splits diagnostics across both.
    public var combined: String { stderr.isEmpty ? stdout : stdout + "\n" + stderr }

    public init(status: Int32, stdout: String, stderr: String) { self.status = status; self.stdout = stdout; self.stderr = stderr }
}

public enum ProofError: Error, CustomStringConvertible {
    case message(String)
    case commandFailed(String, ShellResult)

    public var description: String {
        switch self {
        case .message(let m): return m
        case .commandFailed(let cmd, let r):
            let tail = r.combined.split(separator: "\n").suffix(15).joined(separator: "\n")
            return "command failed (\(r.status)): \(cmd)\n\(tail)"
        }
    }
}

public enum Shell {
    /// Runs a command through /usr/bin/env so PATH lookup works. Captures stdout and stderr.
    /// Pipes are drained concurrently, so large outputs (xcodebuild) never deadlock.
    @discardableResult
    public static func run(
        _ args: [String],
        cwd: String? = nil,
        env: [String: String] = [:],
        stdin: String? = nil,
        tee: FileHandle? = nil
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        process.environment = environment

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe: Pipe? = stdin == nil ? nil : Pipe()
        if let inPipe { process.standardInput = inPipe } else { process.standardInput = FileHandle.nullDevice }

        let lock = NSLock()
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        func drain(_ handle: FileHandle, into append: @escaping (Data) -> Void) {
            group.enter()
            DispatchQueue.global().async {
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    append(chunk)
                }
                group.leave()
            }
        }
        drain(outPipe.fileHandleForReading) { d in lock.lock(); outData.append(d); lock.unlock(); tee?.write(d) }
        drain(errPipe.fileHandleForReading) { d in lock.lock(); errData.append(d); lock.unlock(); tee?.write(d) }

        try process.run()
        let pid = process.processIdentifier
        Interrupt.track(pid)
        defer { Interrupt.untrack(pid) }
        if let inPipe, let stdin {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        group.wait()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Runs and throws when the exit status is non-zero. Returns trimmed stdout.
    @discardableResult
    public static func checked(_ args: [String], cwd: String? = nil, env: [String: String] = [:]) throws -> String {
        let r = try run(args, cwd: cwd, env: env)
        guard r.ok else { throw ProofError.commandFailed(args.joined(separator: " "), r) }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts a detached background process writing to a log file. Returns its pid.
    public static func spawnDetached(_ args: [String], cwd: String? = nil, env: [String: String] = [:], log: String) throws -> Int32 {
        FileManager.default.createFile(atPath: log, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: log) else { throw ProofError.message("cannot open log \(log)") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }

    /// True while the process runs. Reaps it if it is our own exited child (a zombie still answers kill(pid, 0)).
    public static func isAlive(_ pid: Int32) -> Bool {
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid { return false }
        return kill(pid, 0) == 0
    }

    public static func which(_ tool: String) -> String? {
        guard let r = try? run(["which", tool]), r.ok else { return nil }
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

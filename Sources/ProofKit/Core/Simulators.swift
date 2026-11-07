import Foundation

public struct Simulator: Codable, Equatable {
    public let udid: String
    public let name: String
    public let state: String
    public let runtime: String
    public var isBooted: Bool { state == "Booted" }

    /// "iPhone 16 Pro · iOS 26.1"
    public var title: String {
        let version = Simulators.runtimeVersion(runtime).map(String.init).joined(separator: ".")
        return version.isEmpty || version == "0" ? name : "\(name) · iOS \(version)"
    }
}

public enum Simulators {
    struct ListJSON: Decodable {
        struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        let devices: [String: [Device]]
    }

    public static func parse(simctlJSON: String) -> [Simulator] {
        guard let list = try? JSONDecoder().decode(ListJSON.self, from: Data(simctlJSON.utf8)) else { return [] }
        var result: [Simulator] = []
        for (runtime, devices) in list.devices where runtime.contains("iOS") {
            for d in devices where d.isAvailable ?? true {
                result.append(Simulator(udid: d.udid, name: d.name, state: d.state, runtime: runtime))
            }
        }
        // Newest runtime first, so a bare name resolves to the latest iOS.
        return result.sorted { runtimeVersion($1.runtime).lexicographicallyPrecedes(runtimeVersion($0.runtime)) }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" -> [18, 2]
    public static func runtimeVersion(_ runtime: String) -> [Int] {
        guard let r = runtime.range(of: "iOS-") else { return [0] }
        return runtime[r.upperBound...].split(separator: "-").compactMap { Int($0) }
    }

    /// Resolves a name or UDID. Preference: exact UDID, booted with that name, newest runtime with that name.
    /// With no query: the first booted iOS simulator.
    public static func pick(_ query: String?, from sims: [Simulator]) -> Simulator? {
        guard let q = query, !q.isEmpty else { return sims.first(where: \.isBooted) }
        if let s = sims.first(where: { $0.udid == q }) { return s }
        let named = sims.filter { $0.name == q }
        return named.first(where: \.isBooted) ?? named.first
    }

    public static func list() throws -> [Simulator] {
        parse(simctlJSON: try Shell.checked(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    }

    /// Resolves and boots the configured simulator. Returns it in booted state.
    public static func resolveBooted(_ query: String?) throws -> Simulator {
        let sims = try list()
        guard let sim = pick(query, from: sims) else {
            if query == nil { throw ProofError.message("no booted simulator. Set one: proof init --simulator \"iPhone 16\"") }
            throw ProofError.message("simulator not found: \(query!). See: xcrun simctl list devices available")
        }
        if !sim.isBooted {
            _ = try Shell.run(["xcrun", "simctl", "boot", sim.udid])
            _ = try Shell.run(["xcrun", "simctl", "bootstatus", sim.udid, "-b"])
        }
        return Simulator(udid: sim.udid, name: sim.name, state: "Booted", runtime: sim.runtime)
    }

    public static func destination(_ sim: Simulator) -> String { "platform=iOS Simulator,id=\(sim.udid)" }
}

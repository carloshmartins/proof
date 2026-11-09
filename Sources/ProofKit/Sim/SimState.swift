import Foundation

/// Simulator state an agent needs to reach features that start outside the app: deep links, push
/// notifications, privacy permissions and location. Each one is a `proof ui` command and a flow step,
/// run with `xcrun simctl` on the configured simulator (no runner needed).
public enum SimState {
    /// The services `simctl privacy` accepts.
    public static let services = [
        "all", "calendar", "contacts-limited", "contacts", "location", "location-always", "photos-add", "photos",
        "media-library", "microphone", "motion", "reminders", "siri",
    ]

    public struct Command: Equatable {
        public let args: [String]
        public var stdin: String? = nil
        public let detail: String
    }

    /// The simctl command for a state step (open, push, permission, location). Pure, so it is tested.
    public static func command(for step: FlowStep, udid: String, bundleId: String?) throws -> Command {
        func needBundle() throws -> String {
            guard let id = step.option("bundle-id") ?? bundleId else {
                throw ProofError.message("\(step.action): no bundle id. Add --bundle-id or run `proof run` once")
            }
            return id
        }
        switch step.action {
        case "open":
            guard let url = step.positional.first, url.contains(":") else {
                throw ProofError.message("open needs a URL, e.g. open tempo://presets/new")
            }
            return Command(args: ["xcrun", "simctl", "openurl", udid, url], detail: "opened \(url)")

        case "push":
            let id = try needBundle()
            let payload = try pushPayload(step)
            return Command(args: ["xcrun", "simctl", "push", udid, id, "-"], stdin: payload, detail: "pushed to \(id)")

        case "permission":
            let verbs = ["grant", "revoke", "reset"]
            guard step.positional.count == 2, let verb = step.positional.first, verbs.contains(verb) else {
                throw ProofError.message("permission needs grant|revoke|reset and a service, e.g. permission grant photos")
            }
            let service = step.positional[1]
            guard services.contains(service) else {
                throw ProofError.message("unknown service '\(service)'. Known: \(services.joined(separator: ", "))")
            }
            let id = try needBundle()
            let past = ["grant": "granted", "revoke": "revoked", "reset": "reset"][verb]!
            return Command(args: ["xcrun", "simctl", "privacy", udid, verb, service, id], detail: "\(past) \(service) for \(id)")

        case "location":
            if step.flag("clear") {
                return Command(args: ["xcrun", "simctl", "location", udid, "clear"], detail: "location cleared")
            }
            guard let point = step.positional.first, let (lat, lon) = coordinate(point) else {
                throw ProofError.message("location needs latitude,longitude (e.g. location 51.5072,-0.1276) or --clear")
            }
            return Command(args: ["xcrun", "simctl", "location", udid, "set", "\(lat),\(lon)"], detail: "location set to \(lat),\(lon)")

        default:
            throw ProofError.message("not a simulator state step: \(step.action)")
        }
    }

    /// The APNs payload: --payload file.json, or one built from --title, --body, --badge and --sound.
    static func pushPayload(_ step: FlowStep) throws -> String {
        if let path = step.option("payload") {
            guard let data = FileManager.default.contents(atPath: (path as NSString).expandingTildeInPath) else {
                throw ProofError.message("push: cannot read \(path)")
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["aps"] != nil else {
                throw ProofError.message("push: \(path) must be a JSON object with an \"aps\" key")
            }
            return String(decoding: data, as: UTF8.self)
        }
        var alert: [String: Any] = [:]
        if let title = step.option("title") { alert["title"] = title }
        if let body = step.option("body") { alert["body"] = body }
        var aps: [String: Any] = [:]
        if !alert.isEmpty { aps["alert"] = alert }
        if let badge = step.option("badge") {
            guard let n = Int(badge) else { throw ProofError.message("--badge must be a number, got \(badge)") }
            aps["badge"] = n
        }
        if let sound = step.option("sound") { aps["sound"] = sound }
        guard !aps.isEmpty else { throw ProofError.message("push needs --title, --body, --badge or --payload file.json") }
        let data = try JSONSerialization.data(withJSONObject: ["aps": aps], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// "51.5072,-0.1276" → (51.5072, -0.1276), when both are in range.
    static func coordinate(_ s: String) -> (Double, Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    /// Runs a state step on the configured simulator.
    public static func perform(_ step: FlowStep, ctx: Context) throws -> String {
        let sim = try Simulators.resolveBooted(ctx.config.simulator)
        let c = try command(for: step, udid: sim.udid, bundleId: ctx.config.bundleId)
        let r = try Shell.run(c.args, stdin: c.stdin)
        guard r.ok else {
            let message = r.stderr.split(separator: "\n").first.map(String.init) ?? "exit \(r.status)"
            throw ProofError.message("\(step.action) failed: \(message)")
        }
        return c.detail
    }
}

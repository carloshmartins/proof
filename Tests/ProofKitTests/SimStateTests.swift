import XCTest
@testable import ProofKit

final class SimStateTests: XCTestCase {
    func command(_ line: String, bundle: String? = "com.tempo.app") throws -> SimState.Command {
        try SimState.command(for: try XCTUnwrap(try FlowStep.parse(line: line)), udid: "SIM", bundleId: bundle)
    }

    func testOpenURL() throws {
        XCTAssertEqual(try command("open tempo://presets/new").args, ["xcrun", "simctl", "openurl", "SIM", "tempo://presets/new"])
        XCTAssertThrowsError(try command("open presets"))
    }

    func testPushBuildsAPayloadFromOptions() throws {
        let c = try command(#"push --title "Timer done" --body "Take a break" --badge 2"#)
        XCTAssertEqual(c.args, ["xcrun", "simctl", "push", "SIM", "com.tempo.app", "-"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(c.stdin).utf8)) as? [String: Any])
        let aps = try XCTUnwrap(json["aps"] as? [String: Any])
        XCTAssertEqual(aps["badge"] as? Int, 2)
        XCTAssertEqual((aps["alert"] as? [String: String])?["title"], "Timer done")
        XCTAssertThrowsError(try command("push"), "needs content")
        XCTAssertThrowsError(try command("push --badge many"))
        XCTAssertThrowsError(try command("push --title Hi", bundle: nil), "needs a bundle id")
        XCTAssertEqual(try command("push --title Hi --bundle-id other.app", bundle: nil).args[4], "other.app")
    }

    func testPushPayloadFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("p.json"), bad = dir.appendingPathComponent("bad.json")
        try #"{"aps":{"alert":"hi"},"presetId":7}"#.write(to: good, atomically: true, encoding: .utf8)
        try #"{"alert":"hi"}"#.write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertTrue(try command("push --payload \(good.path)").stdin?.contains("presetId") == true)
        XCTAssertThrowsError(try command("push --payload \(bad.path)"), "needs aps")
        XCTAssertThrowsError(try command("push --payload \(dir.path)/missing.json"))
    }

    func testPermission() throws {
        XCTAssertEqual(try command("permission grant photos").args,
                       ["xcrun", "simctl", "privacy", "SIM", "grant", "photos", "com.tempo.app"])
        XCTAssertEqual(try command("permission revoke location").detail, "revoked location for com.tempo.app")
        XCTAssertThrowsError(try command("permission allow photos"))
        XCTAssertThrowsError(try command("permission grant camera"), "simctl can't grant the camera")
        XCTAssertThrowsError(try command("permission grant"))
    }

    func testLocation() throws {
        XCTAssertEqual(try command("location 51.5072,-0.1276").args, ["xcrun", "simctl", "location", "SIM", "set", "51.5072,-0.1276"])
        XCTAssertEqual(try command("location --clear").args, ["xcrun", "simctl", "location", "SIM", "clear"])
        XCTAssertThrowsError(try command("location 91,0"))
        XCTAssertThrowsError(try command("location london"))
    }

    func testStateStepsAreFlowStepsButNotRunnerRequests() throws {
        for line in ["open tempo://x", "push --title a", "permission grant photos", "location 1,2"] {
            let step = try XCTUnwrap(try FlowStep.parse(line: line))
            XCTAssertTrue(FlowStep.simulatorActions.contains(step.action))
            XCTAssertNil(try step.runnerRequest(defaultBundleId: "a"))
        }
    }
}

import XCTest
@testable import ProofKit

final class VariantsTests: XCTestCase {
    func testParsesTokensAndCombinations() throws {
        let v = try SnapVariant.parse("dark+ax5")
        XCTAssertEqual(v.appearance, "dark")
        XCTAssertEqual(v.contentSize, "accessibility-extra-extra-extra-large")
        XCTAssertFalse(v.needsRelaunch)
        XCTAssertEqual(v.snapName("home"), "home@dark+ax5")
        XCTAssertEqual(try SnapVariant.parse("xxl").contentSize, "extra-extra-large")

        let ar = try SnapVariant.parse("ar+rtl")
        XCTAssertEqual(ar.locale, "ar")
        XCTAssertTrue(ar.rightToLeft)
        XCTAssertTrue(ar.needsRelaunch)
        XCTAssertEqual(try SnapVariant.parse("pt-BR").launchArguments, ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"])
        XCTAssertEqual(try SnapVariant.parse("rtl").launchArguments,
                       ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
    }

    func testRejectsNonsense() {
        XCTAssertThrowsError(try SnapVariant.parse("blue"))
        XCTAssertThrowsError(try SnapVariant.parse("dark+light"))
        XCTAssertThrowsError(try SnapVariant.parse("ax1+ax5"))
        XCTAssertThrowsError(try SnapVariant.parseList("dark,dark"))
        XCTAssertEqual(try SnapVariant.parseList(nil), [])
        XCTAssertEqual(try SnapVariant.parseList("dark, ax5").map(\.name), ["dark", "ax5"])
    }

    func testSimulatorCommands() throws {
        XCTAssertEqual(try SnapVariant.parse("light+s").simulatorCommands(udid: "SIM"), [
            ["xcrun", "simctl", "ui", "SIM", "appearance", "light"],
            ["xcrun", "simctl", "ui", "SIM", "content_size", "small"],
        ])
        XCTAssertTrue(try SnapVariant.parse("ar").simulatorCommands(udid: "SIM").isEmpty)
    }

    func testFlowStepsUnderAVariant() throws {
        let v = try SnapVariant.parse("ar")
        let snap = FlowEngine.adapt(try XCTUnwrap(try FlowStep.parse(line: "snap home --variants dark")), to: v)
        XCTAssertEqual(snap.line, "snap home@ar")
        let launch = FlowEngine.adapt(try XCTUnwrap(try FlowStep.parse(line: "launch")), to: v)
        XCTAssertEqual(launch.all("arg"), ["-AppleLanguages", "(ar)", "-AppleLocale", "ar"])
        let tap = try XCTUnwrap(try FlowStep.parse(line: "tap --id x"))
        XCTAssertEqual(FlowEngine.adapt(tap, to: v), tap)
        XCTAssertEqual(FlowEngine.adapt(snap, to: nil), snap)
    }

    func testBaselineKnowsVariantSnapNames() throws {
        let flow = Flow(name: "f", path: "f.flow", steps: [
            try XCTUnwrap(try FlowStep.parse(line: "snap home --variants dark")),
            try XCTUnwrap(try FlowStep.parse(line: "snap settings")),
        ])
        XCTAssertEqual(Baseline.snapNames(flow, variants: [try SnapVariant.parse("ar")]),
                       ["home", "home@dark", "settings", "home@ar", "settings@ar"])
    }

    func testDevices() {
        let d = SnapVariant.parseDevices("iPhone SE (3rd generation), iPad Air 13-inch (M3)")
        XCTAssertEqual(d.map(\.name), ["iphone-se-3rd-generation", "ipad-air-13-inch-m3"])
        XCTAssertEqual(d.first?.device, "iPhone SE (3rd generation)")
        XCTAssertTrue(d[0].needsRelaunch)
        XCTAssertTrue(d[0].launchArguments.isEmpty)
        XCTAssertEqual(d[0].snapName("home"), "home@iphone-se-3rd-generation")
        XCTAssertEqual(SnapVariant.parseDevices(nil), [])
        XCTAssertEqual(SnapVariant.parseDevices(" , "), [])
    }
}

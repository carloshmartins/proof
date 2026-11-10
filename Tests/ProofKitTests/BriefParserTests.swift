import XCTest
@testable import ProofKit

final class BriefParserTests: XCTestCase {
    func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "log", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testBuildFailureIsCondensedAndDeduplicated() throws {
        let r = BriefParser(root: "/Users/me/dev/App").parse(try fixture("build-failed"), action: "build")
        XCTAssertEqual(r.status, "failed")
        XCTAssertEqual(r.warningCount, 1, "repeated warning counted once")
        let messages = r.errors.map(\.message)
        XCTAssertEqual(messages.filter { $0 == "cannot find 'viewModel' in scope" }.count, 1, "summary repeat deduplicated")
        XCTAssertTrue(messages.contains("missing return in instance method expected to return 'Bool'"), "target suffix stripped")
        XCTAssertTrue(messages.contains { $0.contains("undefined symbols: _OBJC_CLASS_$_SyncClient") })
        XCTAssertEqual(r.errors.first?.file, "Modules/Login/Sources/LoginView.swift", "path made relative to root")
        XCTAssertEqual(r.errors.first?.line, 42)
        XCTAssertNil(r.tail)
    }

    func testTestOutputCoversXCTestParallelAndSwiftTesting() throws {
        let r = BriefParser(root: "/Users/me/dev/App").parse(try fixture("test-failed"), action: "test")
        XCTAssertEqual(r.status, "failed")
        let t = try XCTUnwrap(r.tests)
        XCTAssertEqual(t.passed, 3)
        XCTAssertEqual(t.failed, 3)
        XCTAssertEqual(t.skipped, 1)
        let byName = Dictionary(uniqueKeysWithValues: t.failures.map { ($0.test, $0) })
        XCTAssertEqual(byName["LoginViewModelTests/testInvalidPassword"]?.line, 57)
        XCTAssertTrue(byName["LoginViewModelTests/testInvalidPassword"]?.message?.hasPrefix("XCTAssertEqual failed") == true)
        XCTAssertEqual(byName["SyncTests/testReconnect"]?.message, "Asynchronous wait failed: Exceeded timeout of 1 seconds")
        XCTAssertEqual(byName["progressSmoothing()"]?.line, 19)
        XCTAssertTrue(r.errors.isEmpty, "test failures are not build errors")
    }

    func testRenderedTextIsCompact() throws {
        let r = BriefParser(root: "/Users/me/dev/App").parse(try fixture("test-failed"), action: "test", duration: 12.34)
        let lines = r.text.split(separator: "\n")
        XCTAssertEqual(lines.first, "TEST FAILED · 12.3s")
        XCTAssertTrue(lines.contains { $0.hasPrefix("TESTS 3 passed · 3 failed · 1 skipped") })
        XCTAssertTrue(lines.contains { $0.contains("FAIL   LoginViewModelTests/testInvalidPassword  LoginViewModelTests.swift:57") })
    }

    func testSucceededBuild() {
        let r = BriefParser().parse("CompileSwift normal\n** BUILD SUCCEEDED **\n", action: "build")
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.text, "BUILD SUCCEEDED")
    }

    func testUnrecognisedFailureKeepsTail() {
        let r = BriefParser().parse("something odd\nreally odd\n** BUILD FAILED **", action: "build")
        XCTAssertEqual(r.status, "failed")
        XCTAssertEqual(r.tail?.last, "** BUILD FAILED **")
    }

    func testToolLevelErrors() {
        let r = BriefParser().parse("xcodebuild: error: Unable to find a destination matching the provided destination specifier\n", action: "build")
        XCTAssertEqual(r.errors.first?.message, "the simulator isn't available for the scheme. Pick an installed one: proof init --simulator <name>")
        XCTAssertEqual(r.status, "failed")
    }

    func testMacOnlySchemeDestinationError() {
        let log = """
        Command line invocation:
            xcodebuild build -workspace /r/Nub.xcworkspace -scheme Nub -destination "platform=iOS Simulator,id=X"

        xcodebuild: error: Unable to find a destination matching the provided destination specifier:
        \t\t{ platform:iOS Simulator, id:X }

        \tAvailable destinations for the "Nub" scheme:
        \t\t{ platform:macOS, arch:arm64, id:1, name:My Mac }
        \t\t{ platform:macOS, name:Any Mac }

        """
        let r = BriefParser().parse(log, action: "build")
        XCTAssertEqual(r.errors.first?.message,
                       "scheme Nub doesn't build for the iOS Simulator (only macOS). Use the iOS app scheme: proof init --scheme <name>")
    }

    func testNormalizeTestNames() {
        XCTAssertEqual(BriefParser.normalizeTest("-[Mod.Foo testBar]"), "Foo/testBar")
        XCTAssertEqual(BriefParser.normalizeTest("Foo.testBar()"), "Foo/testBar")
        XCTAssertEqual(BriefParser.normalizeTest("Mod.Foo.testBar()"), "Foo/testBar")
        XCTAssertEqual(BriefParser.normalizeTest("\"Parses time presets\""), "Parses time presets")
    }

    func testAppProductFromBuildSettings() {
        let json = """
        [{"target":"AppTests","buildSettings":{"WRAPPER_EXTENSION":"xctest","TARGET_BUILD_DIR":"/x","WRAPPER_NAME":"AppTests.xctest","PRODUCT_BUNDLE_IDENTIFIER":"t"}},
         {"target":"App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/dd/Debug-iphonesimulator","WRAPPER_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.tempo"}}]
        """
        let p = XcodeBuild.parseAppProduct(fromBuildSettingsJSON: json)
        XCTAssertEqual(p?.path, "/dd/Debug-iphonesimulator/App.app")
        XCTAssertEqual(p?.bundleId, "com.example.tempo")
    }

    func testListsSimulatorOnlyFromAvailableDestinations() {
        let mac = """
        \tAvailable destinations for the "Nub" scheme:
        \t\t{ platform:macOS, arch:arm64, id:00006040-001E318A2120801C, name:My Mac }
        \t\t{ platform:macOS, name:Any Mac }

        \tIneligible destinations for the "Nub" scheme:
        \t\t{ platform:iOS Simulator, id:dvtdevice-placeholder, name:Any iOS Simulator Device, error:Nub does not support iOS }
        """
        XCTAssertFalse(XcodeBuild.listsSimulator(showDestinations: mac))
        let ios = """
        \tAvailable destinations for the "NubiOS" scheme:
        \t\t{ platform:iOS Simulator, arch:arm64, id:3520EFF1-126E-4558-ABA8-0DE7D7D654EE, OS:26.5, name:iPhone 17 Pro Max }
        """
        XCTAssertTrue(XcodeBuild.listsSimulator(showDestinations: ios))
    }
}

final class FlakyTestsParsing: XCTestCase {
    func testRetriedTestsAreFlakyOrBroken() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test-retry", withExtension: "log", subdirectory: "Fixtures"))
        let r = BriefParser(root: "/Users/me/dev/App").parse(try String(contentsOf: url, encoding: .utf8), action: "test")
        let t = try XCTUnwrap(r.tests)
        XCTAssertEqual(t.passed, 2)
        XCTAssertEqual(t.failed, 1)
        XCTAssertEqual(t.failures.map(\.test), ["FlakyTests/testAlwaysFails"], "failed every run: broken")
        let flaky = try XCTUnwrap(t.flaky?.first)
        XCTAssertEqual(t.flaky?.count, 1)
        XCTAssertEqual(flaky.test, "FlakyTests/testPassesOnSecondTry")
        XCTAssertEqual(flaky.failedRuns, 1)
        XCTAssertEqual(flaky.runs, 2)
        XCTAssertEqual(flaky.line, 7)
        XCTAssertTrue(r.text.contains("TESTS 2 passed · 1 failed · 1 flaky"), r.text)
        XCTAssertTrue(r.text.contains("FLAKY  FlakyTests/testPassesOnSecondTry  failed 1 of 2 runs  FlakyTests.swift:7"), r.text)
    }

    func testNoRetriesNoFlakyField() throws {
        let r = BriefParser().parse("Test Case '-[A.B testX]' passed (0.1 seconds).\n** TEST SUCCEEDED **", action: "test")
        XCTAssertNil(r.tests?.flaky)
        XCTAssertFalse(r.text.contains("flaky"))
    }
}

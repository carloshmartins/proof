import XCTest
@testable import ProofKit

final class AppProductTests: XCTestCase {
    func entry(_ target: String, platform: String?, dir: String, id: String) -> String {
        let p = platform.map { #","PLATFORM_NAME":"\#($0)""# } ?? ""
        return #"{"target":"\#(target)","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"\#(dir)","WRAPPER_NAME":"\#(target).app","PRODUCT_BUNDLE_IDENTIFIER":"\#(id)"\#(p)}}"#
    }

    /// A workspace scheme that builds a macOS app, example apps and the iOS app.
    func testWorkspaceSchemePicksTheIOSApp() {
        let json = "[" + [
            entry("Nub", platform: "macosx", dir: "/dd/Debug", id: "com.nub.mac"),
            entry("TimerExample", platform: "iphonesimulator", dir: "/dd/Debug-iphonesimulator", id: "com.nub.timer"),
            entry("NubiOS", platform: "iphonesimulator", dir: "/dd/Debug-iphonesimulator", id: "com.nub"),
        ].joined(separator: ",") + "]"
        let p = XcodeBuild.parseAppProduct(fromBuildSettingsJSON: json, scheme: "Nub-Workspace")
        XCTAssertEqual(p?.bundleId, "com.nub")
        XCTAssertEqual(p?.path, "/dd/Debug-iphonesimulator/NubiOS.app")
    }

    func testSchemeNamedTargetWins() {
        let json = "[" + [
            entry("Other", platform: "iphonesimulator", dir: "/d", id: "a"),
            entry("App", platform: "iphonesimulator", dir: "/d", id: "b"),
        ].joined(separator: ",") + "]"
        XCTAssertEqual(XcodeBuild.parseAppProduct(fromBuildSettingsJSON: json, scheme: "App")?.bundleId, "b")
    }

    func testOnlyMacAppsGiveNoProductAndNameThem() {
        let json = "[" + entry("Nub", platform: "macosx", dir: "/dd/Debug", id: "com.nub.mac") + "]"
        XCTAssertNil(XcodeBuild.parseAppProduct(fromBuildSettingsJSON: json, scheme: "Nub"))
        XCTAssertEqual(XcodeBuild.otherPlatformApps(fromBuildSettingsJSON: json), ["Nub (macosx)"])
    }
}

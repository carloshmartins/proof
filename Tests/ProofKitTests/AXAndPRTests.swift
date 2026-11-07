import XCTest
@testable import ProofKit

final class AXScannerTests: XCTestCase {
    let scanner = AXScanner(extraControls: ["PrimaryButton"])

    func lines(_ code: String) -> [Int] { scanner.scanSwift(code, file: "F.swift").map(\.line) }

    func testSwiftUIControls() {
        let code = """
        struct LoginView: View {
            var body: some View {
                VStack {
                    Button("Log in") { submit() }
                        .accessibilityIdentifier("login.submit")
                    Button("Forgot") { forgot() }
                        .padding()
                    Button {
                        cancel()
                    } label: {
                        Text("Cancel (now)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("login.cancel")
                    TextField("Email", text: $email)
                    Toggle(isOn: $remember) { Text("Remember") }.accessibilityIdentifier("login.remember")
                    PrimaryButton(title: "Go")
                }
            }
        }
        """
        XCTAssertEqual(lines(code), [6, 15, 17])
    }

    func testStringsAndCommentsDoNotConfuseScanning() {
        let code = """
        let s = "Button(\\"not code\\") { "
        // Button("commented out")
        /* Button("block") */
        let raw = #"Toggle(isOn:)"#
        let multi = \"\"\"
        TextField("in multiline")
        \"\"\"
        Button("Real \\(count) items)") { }
            .accessibilityIdentifier("real")
        Button("Missing") { }
        """
        XCTAssertEqual(lines(code), [10])
    }

    func testPreviewsDeclarationsAndMemberAccessAreSkipped() {
        let code = """
        struct Button: View { var body: some View { EmptyView() } }
        let style = ButtonStyle.self
        let x = Foo.Button("no")
        #Preview {
            Button("Preview only") { }
        }
        struct Old_Previews: PreviewProvider {
            static var previews: some View { Toggle("x", isOn: .constant(true)) }
        }
        """
        XCTAssertEqual(lines(code), [])
    }

    func testIgnoreMarker() {
        let code = """
        // proof:ignore
        Button("A") { }
        Button("B") { } // proof:ignore
        """
        XCTAssertEqual(lines(code), [])
    }

    func testUIKit() {
        let code = """
        final class VC: UIViewController {
            private let saveButton = UIButton(type: .system)
            private let nameField: UITextField = UITextField()
            private lazy var toggle: UISwitch = {
                let s = UISwitch()
                s.accessibilityIdentifier = "settings.toggle"
                return s
            }()
            override func viewDidLoad() {
                saveButton.accessibilityIdentifier = "settings.save"
                let config = UIButton.Configuration.filled()
            }
        }
        """
        let findings = scanner.scanSwift(code, file: "VC.swift")
        XCTAssertEqual(findings.map(\.line), [3])
        XCTAssertEqual(findings.first?.control, "UITextField")
    }

    func testInterfaceBuilder() {
        let xib = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB">
          <objects>
            <view key="view">
              <subviews>
                <button opaque="NO" id="a1">
                  <state key="normal" title="Save"/>
                  <accessibility key="accessibilityConfiguration" identifier="settings.save"/>
                </button>
                <button opaque="NO" id="a2">
                  <state key="normal" title="Delete"/>
                </button>
                <textField placeholder="Name" id="a3"/>
              </subviews>
            </view>
          </objects>
        </document>
        """
        let findings = scanner.scanInterfaceBuilder(xib, file: "Settings.xib")
        XCTAssertEqual(findings.map(\.snippet), ["<button \"Delete\">", "<textField \"Name\">"])
    }

    func testDirectoryScanSkipsBuildFoldersAndTests() throws {
        let tmp = NSTemporaryDirectory() + "axscan-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmp + "/App/Sources", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmp + "/App/AppTests", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmp + "/.build/x", withIntermediateDirectories: true)
        try "Button(\"a\") { }".write(toFile: tmp + "/App/Sources/A.swift", atomically: true, encoding: .utf8)
        try "Button(\"b\") { }".write(toFile: tmp + "/App/AppTests/B.swift", atomically: true, encoding: .utf8)
        try "Button(\"c\") { }".write(toFile: tmp + "/.build/x/C.swift", atomically: true, encoding: .utf8)
        let report = AXScanner().scan(paths: [tmp], root: tmp)
        XCTAssertEqual(report.findings.map(\.file), ["App/Sources/A.swift"])
        XCTAssertTrue(report.text.hasPrefix("AX SCAN 1 missing identifier in 1 file"))
        try? fm.removeItem(atPath: tmp)
    }
}

final class PRCommentsTests: XCTestCase {
    let json = """
    {"data":{"repository":{"pullRequest":{"number":42,"title":"Add device pairing","url":"https://github.com/o/r/pull/42",
     "reviewThreads":{"nodes":[
       {"isResolved":false,"isOutdated":false,"path":"Sync/Pairing.swift","line":12,"originalLine":12,
        "comments":{"nodes":[{"author":{"login":"alice"},"body":"Use the shared scanner here.<!-- hidden -->"},
                             {"author":{"login":"bob"},"body":"Agreed"}]}},
       {"isResolved":true,"isOutdated":false,"path":"A.swift","line":1,"originalLine":1,
        "comments":{"nodes":[{"author":{"login":"alice"},"body":"done"}]}},
       {"isResolved":false,"isOutdated":true,"path":"B.swift","line":null,"originalLine":7,
        "comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"body":"Consider a guard.\\n\\n\\n\\n<details>long</details>"}]}}
     ]},
     "reviews":{"nodes":[{"author":{"login":"carol"},"state":"CHANGES_REQUESTED","body":"See threads"},
                         {"author":{"login":"dave"},"state":"COMMENTED","body":""}]},
     "comments":{"nodes":[{"author":{"login":"erin"},"body":"Ship it after CI"}]}
    }}}}
    """

    func testDefaultHidesResolvedAndCleansBodies() throws {
        let r = try PRComments.report(fromJSON: json, options: .init())
        XCTAssertEqual(r.threads.count, 2)
        XCTAssertEqual(r.resolvedHidden, 1)
        XCTAssertEqual(r.threads[0].comments[0].body, "Use the shared scanner here.")
        XCTAssertEqual(r.threads[1].line, 7, "falls back to originalLine for outdated threads")
        XCTAssertEqual(r.threads[1].comments[0].body, "Consider a guard.\n\n[details omitted]")
        XCTAssertEqual(r.reviews.count, 1, "empty COMMENTED reviews dropped")
        XCTAssertTrue(r.text.hasPrefix("PR #42 \"Add device pairing\" · 2 threads (1 resolved hidden) · 1 review · 1 comment"))
        XCTAssertTrue(r.text.contains("[1] Sync/Pairing.swift:12\n    @alice: Use the shared scanner here.\n    ↳ @bob: Agreed"))
    }

    func testNoBotsAndTruncation() throws {
        var o = PRComments.Options()
        o.includeBots = false
        o.maxBody = 10
        let r = try PRComments.report(fromJSON: json, options: o)
        XCTAssertEqual(r.threads.count, 1)
        XCTAssertEqual(r.threads[0].comments[0].body, "Use the sh …[truncated]")
    }
}

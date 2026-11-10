import XCTest
@testable import ProofKit

final class OutputBudgetTests: XCTestCase {
    func testBudgetKeepsTheHead() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let (shown, cut) = Output.budget(text, maxLines: 4)
        XCTAssertEqual(shown, "line 1\nline 2\nline 3")
        XCTAssertEqual(cut, 7)
        XCTAssertEqual(Output.budget(text, maxLines: 10).cut, 0, "fits")
        XCTAssertEqual(Output.budget(text, maxLines: nil).text, text)
        XCTAssertEqual(Output.budget(text, maxLines: 1).text, "line 1", "always keeps the verdict line")
    }

    func testTreeDepth() {
        let nodes = [UINode(type: "window", depth: 1), UINode(type: "other", depth: 2), UINode(type: "button", depth: 3)]
        XCTAssertEqual(UITree.limit(nodes, depth: 1).map(\.type), ["window", "other"])
        XCTAssertEqual(UITree.limit(nodes, depth: 0).map(\.type), ["window"])
    }
}

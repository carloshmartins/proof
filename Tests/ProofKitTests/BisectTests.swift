import XCTest
@testable import ProofKit

final class BisectTests: XCTestCase {
    func run(_ n: Int, firstBad: Int, skip: Set<Int> = []) -> (Int?, Range<Int>, [Int]) {
        var asked: [Int] = []
        let r = Bisect.search(n) { i in
            asked.append(i)
            if skip.contains(i) { return .skip }
            return i >= firstBad ? .bad : .good
        }
        return (r.first, r.candidates, asked)
    }

    func testFindsTheFirstBadCommitInLogSteps() {
        for n in 1...40 {
            for firstBad in 0..<n {
                let (found, _, asked) = run(n, firstBad: firstBad)
                XCTAssertEqual(found, firstBad, "n=\(n) firstBad=\(firstBad)")
                XCTAssertLessThanOrEqual(asked.count, Int(ceil(log2(Double(n)))) + 1)
                XCTAssertFalse(asked.contains(n - 1), "the known bad end isn't asked again")
            }
        }
    }

    func testSkipsCommitsThatDontBuild() {
        let (found, _, asked) = run(10, firstBad: 6, skip: [4])
        XCTAssertEqual(found, 6)
        XCTAssertTrue(asked.contains(4))
    }

    func testAmbiguousWhenSkipsHideTheAnswer() {
        let (found, candidates, _) = run(10, firstBad: 6, skip: [5, 6])
        XCTAssertNil(found)
        XCTAssertEqual(candidates, 5..<8)
    }

    func testReportText() {
        var r = BisectReport(check: "screen home changes", good: "aaaaaaa", bad: "bbbbbbb")
        r.steps = [.init(sha: "bbbbbbb", subject: "Tidy", verdict: .bad), .init(sha: "ccccccc", subject: "Rename label", verdict: .bad)]
        r.culprit = .init(sha: "ccccccc", subject: "Rename label", verdict: .bad)
        XCTAssertEqual(r.text, """
        BISECT screen home changes first in ccccccc Rename label · 2 commits checked
          bbbbbbb bad   Tidy
          ccccccc bad   Rename label
        """)
    }
}

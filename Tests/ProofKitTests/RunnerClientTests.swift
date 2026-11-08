import XCTest
@testable import ProofKit

final class RunnerClientTests: XCTestCase {
    func testHealthMatchesOnlyTheExpectedSession() {
        XCTAssertTrue(Runner.healthMatches(["ok": true, "session": "A"], session: "A"))
        XCTAssertFalse(Runner.healthMatches(["ok": true, "session": "OLD"], session: "A"), "a runner still shutting down")
        XCTAssertFalse(Runner.healthMatches(["ok": true], session: "A"), "a runner from an older proof")
        XCTAssertTrue(Runner.healthMatches(["ok": true], session: nil), "no session expected")
        XCTAssertFalse(Runner.healthMatches(["ok": false, "session": "A"], session: "A"))
    }

    func testRetriesConnectionErrorsOnlyRightAfterAStart() {
        let lost = URLError(.networkConnectionLost)
        XCTAssertEqual(Runner.retryDelay(for: lost, attempt: 0, sinceStart: 1), 0.5)
        XCTAssertEqual(Runner.retryDelay(for: URLError(.cannotConnectToHost), attempt: 2, sinceStart: 3), 1.5)
        XCTAssertNil(Runner.retryDelay(for: lost, attempt: 4, sinceStart: 3), "gives up after 4 retries")
        XCTAssertNil(Runner.retryDelay(for: lost, attempt: 0, sinceStart: 60), "a runner that has been up")
        XCTAssertNil(Runner.retryDelay(for: lost, attempt: 0, sinceStart: nil), "found already running")
        XCTAssertNil(Runner.retryDelay(for: URLError(.badServerResponse), attempt: 0, sinceStart: 1))
        XCTAssertNil(Runner.retryDelay(for: ProofError.message("element not found"), attempt: 0, sinceStart: 1))
    }

    func testOlderStateFilesDecodeWithoutSession() throws {
        let json = #"{"pid":1,"port":22087,"udid":"X","sourceStamp":"s"}"#
        let state = try JSONDecoder().decode(RunnerState.self, from: Data(json.utf8))
        XCTAssertNil(state.session)
    }
}

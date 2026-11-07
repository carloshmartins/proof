import XCTest
@testable import Tempo

final class TimerTests: XCTestCase {
    func testStartsAtTwentyFiveMinutes() {
        XCTAssertEqual(TimerModel().label, "25:00")
    }

    func testStartAndStop() {
        let model = TimerModel()
        model.start()
        XCTAssertTrue(model.isRunning)
        model.stop()
        XCTAssertFalse(model.isRunning)
    }
}

import XCTest
@testable import Tempo

final class PresetTests: XCTestCase {
    func testDefaultIsFocus() {
        XCTAssertEqual(PresetStore().selected, Preset(name: "Focus", minutes: 25))
    }

    func testSelect() {
        let store = PresetStore()
        store.select(Preset.all[1])
        XCTAssertEqual(store.selected.minutes, 5)
    }
}

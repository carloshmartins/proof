import XCTest
@testable import Tempo

final class PresetTests: XCTestCase {
    private func storage() -> UserDefaults { UserDefaults(suiteName: "PresetTests-\(UUID().uuidString)")! }

    func testDefaultIsFocus() {
        XCTAssertEqual(PresetStore(storage: storage()).selected.name, "Focus")
    }

    func testSelect() {
        let store = PresetStore(storage: storage())
        store.select(Preset.all[1])
        XCTAssertEqual(store.selected.name, "Short break")
    }
}

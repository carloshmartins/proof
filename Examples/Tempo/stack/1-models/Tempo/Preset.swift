import Foundation

struct Preset: Codable, Equatable {
    let name: String
    let minutes: Int

    static let all = [Preset(name: "Focus", minutes: 25), Preset(name: "Short break", minutes: 5)]
}

/// The preset the timer starts from.
final class PresetStore {
    private(set) var selected = Preset.all[0]

    func select(_ preset: Preset) { selected = preset }
}

import Foundation

struct Preset: Codable, Equatable {
    let name: String
    let minutes: Int

    static let all = [Preset(name: "Focus", minutes: 25), Preset(name: "Short break", minutes: 5)]
}

/// The preset the timer starts from, remembered between launches.
final class PresetStore {
    private let storage: UserDefaults

    init(storage: UserDefaults = .standard) { self.storage = storage }

    var selected: Preset {
        let name = storage.string(forKey: "preset.name") ?? Preset.all[0].name
        let minutes = storage.object(forKey: "preset.minute") as? Int ?? Preset.all[0].minutes
        return Preset(name: name, minutes: minutes)
    }

    func select(_ preset: Preset) {
        storage.set(preset.name, forKey: "preset.name")
        storage.set(preset.minutes, forKey: "preset.minutes")
    }
}

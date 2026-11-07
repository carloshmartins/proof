import Foundation

/// A focus timer. Starts at 25 minutes.
final class TimerModel: ObservableObject {
    @Published private(set) var minutes = 25
    @Published private(set) var isRunning = false

    var label: String { String(format: "%02d:00", minutes) }

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

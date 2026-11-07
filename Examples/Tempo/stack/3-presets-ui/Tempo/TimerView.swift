import SwiftUI

struct TimerView: View {
    @StateObject private var model = TimerModel()
    @State private var showPresets = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Tempo").font(.largeTitle.bold())
                .accessibilityIdentifier("timer.title")
            Text(model.label).font(.system(size: 72, weight: .light, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("timer.time")
            if model.isRunning {
                Text("Running").foregroundStyle(.green)
                    .accessibilityIdentifier("timer.running")
            }
            Button(model.isRunning ? "Stop" : "Start \(model.label)") {
                model.isRunning ? model.stop() : model.start()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("timer.start")
            Button("Presets") { showPresets = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("timer.presets")
        }
        .padding()
        .sheet(isPresented: $showPresets) {
            List(Preset.all, id: \.name) { preset in
                Text("\(preset.name) · \(preset.minutes) min")
            }
            .accessibilityIdentifier("presets.list")
        }
    }
}

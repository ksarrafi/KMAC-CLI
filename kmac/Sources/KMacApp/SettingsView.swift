import SwiftUI
import Foundation

/// Lightweight settings: how often to sample health, and which Claude model is
/// in effect. The model is controlled by the KMAC_CLAUDE_MODEL environment
/// variable (read by KMacCore), so it is shown read-only here.
struct SettingsView: View {
    @ObservedObject var health: HealthStore
    @AppStorage("kmac.pollIntervalSeconds") private var pollInterval: Double = 5

    private var currentModel: String {
        ProcessInfo.processInfo.environment["KMAC_CLAUDE_MODEL"] ?? "claude-sonnet-4-6"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Health poll interval: \(Int(pollInterval))s")
                Slider(value: $pollInterval, in: 2...60, step: 1) {
                    Text("Interval")
                }
                .onChange(of: pollInterval) { newValue in
                    health.restartPolling(interval: newValue)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Claude model").font(.headline)
                Text(currentModel).font(.callout.monospaced())
                Text("Set KMAC_CLAUDE_MODEL to override; key is read from the KMac vault.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 420, height: 260)
    }
}

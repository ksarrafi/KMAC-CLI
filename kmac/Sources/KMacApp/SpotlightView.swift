import SwiftUI
import KMacCore

/// The Cmd+K panel content: a live system-health header and an ask-Claude box
/// whose answer streams in. All data comes from the shared KMacCore engine via
/// HealthStore and ClaudeAPI.
struct SpotlightView: View {
    @ObservedObject var health: HealthStore
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var answer: String = ""
    @State private var asking: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Ask Claude about your Mac…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(ask)
                if asking { ProgressView().controlSize(.small) }
            }

            if !answer.isEmpty {
                Divider()
                ScrollView {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear { fieldFocused = true }
    }

    private var statusHeader: some View {
        HStack(spacing: 16) {
            metric("CPU", health.snapshot?.cpuUsage)
            metric("Memory", health.snapshot?.memoryUsage)
            metric("Disk", health.snapshot?.diskUsage)
            Spacer()
            if let status = health.snapshot?.status {
                Text(status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.2), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
    }

    private func metric(_ name: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.title3.monospacedDigit())
        }
    }

    private func statusColor(_ s: SystemHealthStatus) -> Color {
        switch s {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        asking = true
        answer = ""
        let context = health.claudeContext
        Task {
            do {
                let api = try ClaudeAPI()
                for await chunk in api.askClaude(query: q, systemContext: context) {
                    answer += chunk
                }
            } catch {
                answer = "Error: \(error.localizedDescription)"
            }
            asking = false
        }
    }
}

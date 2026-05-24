import SwiftUI
import KMacCore

/// Deterministic playbooks as one-click actions — the primary, zero-cost path.
/// Inspect (read-only) shows what would change; Run applies it (confirming if
/// destructive). No LLM involved.
@MainActor
final class PlaybooksModel: ObservableObject {
    @Published var output: [String: String] = [:]   // playbook id -> last output
    @Published var busy: String?                     // id currently running

    func inspect(_ pb: Playbook) async {
        busy = pb.id; defer { busy = nil }
        output[pb.id] = await run(pb.inspect)
    }

    func apply(_ pb: Playbook, health: HealthStore) async {
        busy = pb.id; defer { busy = nil }
        output[pb.id] = await run(pb.apply)
        await health.refresh()
    }

    private func run(_ command: String) async -> String {
        do {
            return try await FixExecutor.executeCommand(command)
        } catch let FixExecutionError.commandFailed(_, out) {
            return out
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

struct PlaybooksView: View {
    @ObservedObject var health: HealthStore
    @StateObject private var model = PlaybooksModel()
    @State private var confirming: Playbook?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Playbooks").font(.title3.bold())
                Text("Deterministic, repeatable fixes — no AI, no cost.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(Playbooks.all) { pb in
                    card(pb)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 480)
        .alert(item: $confirming) { pb in
            Alert(
                title: Text("Run “\(pb.title)”?"),
                message: Text(pb.summary + "\n\nThis modifies files on your Mac."),
                primaryButton: .destructive(Text("Run")) {
                    Task { await model.apply(pb, health: health) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func card(_ pb: Playbook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pb.title).font(.headline)
                        if pb.destructive {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(pb.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy == pb.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Inspect") { Task { await model.inspect(pb) } }
                    Button("Run") {
                        if pb.destructive { confirming = pb }
                        else { Task { await model.apply(pb, health: health) } }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let out = model.output[pb.id], !out.isEmpty {
                ScrollView {
                    Text(out)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

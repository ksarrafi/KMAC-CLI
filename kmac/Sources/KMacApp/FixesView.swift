import SwiftUI
import KMacCore

/// Drives the Fixes window: asks Claude for fixes based on the current health
/// issues, lists them, and runs a chosen one through FixExecutor. All backend
/// work goes through KMacCore — no logic duplicated here.
@MainActor
final class FixesModel: ObservableObject {
    @Published var fixes: [SuggestedFix] = []
    @Published var loading = false
    @Published var status: String?
    @Published var runningCommand: String?
    @Published var lastResult: String?

    /// Loads any previously saved fixes from the shared store.
    func loadSaved() {
        fixes = FixStore.load()
    }

    /// Asks Claude for fixes for the given issues and persists them.
    func fetchFixes(issues: [String], context: String) async {
        guard !loading else { return }
        loading = true
        status = nil
        defer { loading = false }

        let prompt: String
        if issues.isEmpty {
            prompt = "Suggest preventative maintenance commands for this Mac. "
                + "Return each as a bash code block."
        } else {
            prompt = "System has these issues: \(issues.joined(separator: ", ")). "
                + "Provide specific terminal commands to fix them, each in a bash code block."
        }

        do {
            let api = try ClaudeAPI()
            var full = ""
            for await chunk in api.askClaude(query: prompt, systemContext: context) {
                full += chunk
            }
            let parsed = api.parseSuggestedFixes(response: full)
            fixes = parsed
            if parsed.isEmpty {
                status = "No actionable fixes found in the response."
            } else {
                try? FixStore.save(parsed)
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    /// Executes a fix (caller confirms first).
    func run(_ fix: SuggestedFix) async {
        runningCommand = fix.command
        lastResult = nil
        defer { runningCommand = nil }
        let record = try? await FixExecutor.executeFixWithConfirmation(fix)
        if let record {
            lastResult = (record.success ? "✓ " : "✗ ") + (record.output.isEmpty ? "(no output)" : record.output)
        } else {
            lastResult = "✗ Execution failed to start."
        }
    }
}

struct FixesView: View {
    @ObservedObject var health: HealthStore
    @StateObject private var model = FixesModel()
    @State private var confirming: SuggestedFix?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Issues & Fixes").font(.title3.bold())
                Spacer()
                Button(model.loading ? "Asking…" : "Get Fixes") {
                    let issues = health.issues
                    let context = health.claudeContext
                    Task { await model.fetchFixes(issues: issues, context: context) }
                }
                .disabled(model.loading)
            }

            issuesSection

            Divider()

            if model.fixes.isEmpty {
                Text(model.status ?? "No fixes yet. Press “Get Fixes”.")
                    .foregroundStyle(.secondary)
            } else {
                fixesList
            }

            if let result = model.lastResult {
                Divider()
                ScrollView { Text(result).font(.callout.monospaced()).textSelection(.enabled) }
                    .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .frame(width: 560, height: 460)
        .onAppear(perform: model.loadSaved)
        .alert(item: $confirming) { fix in
            Alert(
                title: Text("Run this fix?"),
                message: Text(fix.command),
                primaryButton: .destructive(Text("Run")) {
                    Task { await model.run(fix) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var issuesSection: some View {
        Group {
            if health.issues.isEmpty {
                Label("No issues detected", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(health.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var fixesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.fixes.enumerated()), id: \.offset) { _, fix in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fix.title).font(.headline)
                            Spacer()
                            Button("Run") { confirming = fix }
                                .disabled(model.runningCommand != nil)
                        }
                        if !fix.description.isEmpty {
                            Text(fix.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(fix.command)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

// Allow SuggestedFix to drive a SwiftUI .alert(item:).
extension SuggestedFix: Identifiable {
    public var id: String { title + command }
}

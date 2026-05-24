import SwiftUI
import KMacCore

/// The Cmd+K panel content: a live system-health header and an ask-Claude box
/// whose answer streams in. All data comes from the shared KMacCore engine via
/// HealthStore and ClaudeAPI.
struct SpotlightView: View {
    @ObservedObject var health: HealthStore
    @ObservedObject var input: PanelInput
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var answer: String = ""
    @State private var asking: Bool = false
    @State private var fixes: [SuggestedFix] = []
    @State private var confirming: SuggestedFix?
    @State private var runResult: String?
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
                if asking {
                    ProgressView().controlSize(.small)
                } else {
                    // Explicit Return-bound trigger: onSubmit alone is unreliable
                    // for a TextField hosted in a borderless NSPanel.
                    Button("Ask", action: ask)
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if answer.isEmpty {
                        Text("Answers appear here. Type a question and press Return or click Ask.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(markdown(answer))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !fixes.isEmpty { fixesSection }

                    if let runResult {
                        Text(runResult)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(width: 560, height: 460, alignment: .top)
        .onAppear {
            fieldFocused = true
            consumePendingQuestion()
        }
        .onChange(of: input.pendingQuestion) { _ in
            consumePendingQuestion()
        }
        .alert(item: $confirming) { fix in
            Alert(
                title: Text("Run this fix?"),
                message: Text(fix.command),
                primaryButton: .destructive(Text("Run")) { Task { await run(fix) } },
                secondaryButton: .cancel()
            )
        }
    }

    /// Runnable fixes parsed from the answer — the actionable part: each has a
    /// Run button that confirms then executes via KMacCore's FixExecutor.
    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Runnable fixes").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(Array(fixes.enumerated()), id: \.offset) { _, fix in
                HStack(alignment: .top, spacing: 8) {
                    Text(fix.command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Run") { confirming = fix }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private func run(_ fix: SuggestedFix) async {
        runResult = "Running: \(fix.command)…"
        let record = try? await FixExecutor.executeFixWithConfirmation(fix)
        if let record {
            runResult = (record.success ? "✓ " : "✗ ") + (record.output.isEmpty ? "(done, no output)" : record.output)
            await health.refresh()
        } else {
            runResult = "✗ Failed to start."
        }
    }

    /// When a question is pushed in from outside (e.g. a `kmac://ask?q=…` URL),
    /// fill the field, submit it, and clear the channel.
    private func consumePendingQuestion() {
        guard let q = input.pendingQuestion else { return }
        input.pendingQuestion = nil
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        query = trimmed
        ask()
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
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
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
        fixes = []
        runResult = nil
        let context = health.claudeContext
        // Must run on the main actor: this mutates @State (answer/asking) as
        // chunks stream in, and SwiftUI state must be updated on the main thread.
        Task { @MainActor in
            do {
                let api = try ClaudeAPI()
                for await chunk in api.askClaude(query: q, systemContext: context) {
                    answer += chunk
                }
                fixes = api.parseSuggestedFixes(response: answer)
            } catch {
                answer = "Error: \(error.localizedDescription)"
            }
            asking = false
        }
    }
}

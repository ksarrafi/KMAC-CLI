import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    @State private var session: AgentSession?
    @State private var outputLines: [String] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var refreshTimer: Timer?
    @FocusState private var isInputFocused: Bool

    private var isRunning: Bool { session?.running ?? false }
    private var isIdle: Bool { session?.status == "idle" }

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if outputLines.isEmpty && isIdle {
                            VStack(spacing: 12) {
                                Image(systemName: "brain")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple.opacity(0.5))
                                Text("Type a message to start \(session?.agentLabel ?? "the agent")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }

                        ForEach(Array(outputLines.enumerated()), id: \.offset) { idx, line in
                            if line.hasPrefix("▶ ") {
                                Text(line)
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundStyle(.blue)
                                    .textSelection(.enabled)
                                    .id(idx)
                            } else {
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                .onTapGesture { isInputFocused = true }
                .onChange(of: outputLines.count) { _, newCount in
                    guard newCount > 0 else { return }
                    withAnimation { proxy.scrollTo(newCount - 1) }
                }
            }

            // Input bar
            VStack(spacing: 6) {
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Agent is working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            stopSession()
                        } label: {
                            Text("Stop")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(.purple)

                    TextField(isRunning ? "Waiting for agent..." : "Type a message...", text: $inputText)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isInputFocused)
                        .disabled(isRunning || isSending)
                        .onSubmit { sendMessage() }

                    if isSending {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { sendMessage() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(inputText.isEmpty || isRunning ? .gray : .purple)
                        }
                        .disabled(inputText.isEmpty || isRunning)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
        .navigationTitle(session?.project ?? "Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let session {
                    HStack(spacing: 8) {
                        Text(session.agentLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(isRunning ? .green : statusColor(session.status))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .onAppear {
            loadSession()
            startPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInputFocused = true
            }
        }
        .onDisappear { stopPolling() }
    }

    // MARK: - Actions

    private func sendMessage() {
        let msg = inputText.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        inputText = ""
        isSending = true

        Task { @MainActor in
            guard let api = appState.api else { return }
            _ = try? await api.sendMessage(id: sessionId, message: msg)
            isSending = false
            // Refresh to pick up new output
            await refreshOutput()
        }
    }

    private func stopSession() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            _ = try? await api.stopSession(id: sessionId)
            await refreshOutput()
        }
    }

    private func loadSession() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            session = try? await api.sessionDetail(id: sessionId)
            let output = try? await api.sessionOutput(id: sessionId, tail: 500)
            outputLines = output?.lines ?? []
        }
    }

    private func refreshOutput() async {
        guard let api = appState.api else { return }
        session = try? await api.sessionDetail(id: sessionId)
        if let output = try? await api.sessionOutput(id: sessionId, tail: 500) {
            if output.total != outputLines.count {
                outputLines = output.lines
            }
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in await refreshOutput() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "idle": return .purple
        case "completed": return .blue
        case "failed": return .red
        case "stopped": return .orange
        default: return .gray
        }
    }
}

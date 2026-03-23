import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var appState: AppState
    @State private var command = ""
    @State private var history: [(cmd: String, output: String, exitCode: Int)] = []
    @State private var isRunning = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Output area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            // Live agent output
                            if !appState.ws.outputLines.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Image(systemName: "brain")
                                            .foregroundStyle(.purple)
                                        Text("Agent Output")
                                            .font(.caption.bold())
                                            .foregroundStyle(.purple)
                                    }
                                    ForEach(Array(appState.ws.outputLines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.bottom, 8)
                                Divider()
                            }

                            // Command history
                            ForEach(Array(history.enumerated()), id: \.offset) { idx, entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text("$")
                                            .foregroundStyle(.blue)
                                        Text(entry.cmd)
                                            .foregroundStyle(.white)
                                    }
                                    .font(.system(.caption, design: .monospaced).bold())

                                    Text(entry.output)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(entry.exitCode == 0 ? .white.opacity(0.8) : .red)
                                }
                                .id(idx)
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)
                    .onTapGesture { isInputFocused = true }
                    .onChange(of: history.count) { _, _ in
                        guard history.count > 0 else { return }
                        withAnimation {
                            proxy.scrollTo(history.count - 1)
                        }
                    }
                }

                // Input bar
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(.blue)

                    TextField("command", text: $command)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.send)
                        .focused($isInputFocused)
                        .onSubmit { runCommand() }

                    if isRunning {
                        ProgressView()
                    } else {
                        Button { runCommand() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(command.isEmpty)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Terminal")
            .onAppear { isInputFocused = true }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        history = []
                        appState.ws.clearOutput()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func runCommand() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        command = ""
        isRunning = true

        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let project = appState.selectedProject?.name ?? appState.taskStatus?.task.project ?? ""
                let result = try await api.run(command: cmd, project: project)
                history.append((
                    cmd: cmd,
                    output: result.output ?? result.error ?? "(no output)",
                    exitCode: result.exitCode ?? -1
                ))
            } catch {
                history.append((cmd: cmd, output: error.localizedDescription, exitCode: -1))
            }
            isRunning = false
            isInputFocused = true
        }
    }
}

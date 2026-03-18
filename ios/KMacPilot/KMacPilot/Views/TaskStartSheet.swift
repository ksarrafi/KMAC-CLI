import SwiftUI

struct TaskStartSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var preselectedProject: String = ""
    @State var preselectedAgent: String = ""
    @State private var agent = "claude"
    @State private var isStarting = false
    @State private var error: String?

    var onSessionCreated: ((AgentSession) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    if !preselectedProject.isEmpty {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(preselectedProject)
                                .bold()
                        }
                    } else {
                        Picker("Select Project", selection: $preselectedProject) {
                            Text("Choose...").tag("")
                            ForEach(appState.projects) { p in
                                Text(p.name).tag(p.name)
                            }
                        }
                    }
                }

                Section("AI Agent") {
                    Picker("Agent", selection: $agent) {
                        Label("Claude Code", systemImage: "brain").tag("claude")
                        Label("Cursor Agent", systemImage: "cursorarrow.rays").tag("cursor")
                    }
                    .pickerStyle(.segmented)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        startSession()
                    } label: {
                        if isStarting {
                            ProgressView()
                        } else {
                            Text("Start")
                                .bold()
                        }
                    }
                    .disabled(preselectedProject.isEmpty || isStarting)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if !preselectedAgent.isEmpty {
                agent = preselectedAgent
            }
        }
    }

    private func startSession() {
        isStarting = true
        error = nil
        Task {
            guard let api = appState.api else { return }
            do {
                let result = try await api.createSession(
                    project: preselectedProject,
                    prompt: "",
                    agent: agent
                )
                if result.ok == true, let session = result.session {
                    await appState.refreshStatus()
                    dismiss()
                    onSessionCreated?(session)
                } else {
                    self.error = result.error ?? "Failed to create task"
                }
            } catch {
                self.error = error.localizedDescription
            }
            isStarting = false
        }
    }
}

import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewTask = false
    @State private var refreshTimer: Timer?
    @State private var navigateToSession: AgentSession?

    private var activeSessions: [AgentSession] {
        appState.agentSessions.filter { $0.running || $0.isIdle }
    }

    private var completedSessions: [AgentSession] {
        appState.agentSessions.filter { !$0.running && !$0.isIdle }
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeSessions.isEmpty {
                    Section("Active") {
                        ForEach(activeSessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                        }
                    }
                }

                if !completedSessions.isEmpty {
                    Section("History") {
                        ForEach(completedSessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { offsets in
                            deleteSessions(at: offsets)
                        }
                    }
                }

                if appState.agentSessions.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "brain",
                        description: Text("Start a task to get an AI agent working on a project")
                    )
                }
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: AgentSession.self) { session in
                SessionDetailView(sessionId: session.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { @MainActor in await appState.refreshStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showNewTask) {
                TaskStartSheet(onSessionCreated: { session in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToSession = session
                    }
                })
            }
            .navigationDestination(item: $navigateToSession) { session in
                SessionDetailView(sessionId: session.id)
            }
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        let toDelete = offsets.map { completedSessions[$0] }
        Task { @MainActor in
            guard let api = appState.api else { return }
            for session in toDelete {
                do {
                    _ = try await api.deleteSession(id: session.id)
                } catch {
                    appState.errorMessage = error.localizedDescription
                }
            }
            await appState.refreshStatus()
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in await appState.refreshStatus() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.project)
                        .font(.body.bold())
                    Text("· \(session.agentLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(session.task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(session.status)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor)
                    Text("· \(session.outputLines) lines")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.status {
        case "running": return .green
        case "idle": return .purple
        case "completed": return .blue
        case "failed": return .red
        case "stopped": return .orange
        default: return .gray
        }
    }
}

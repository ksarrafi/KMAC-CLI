import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showTaskSheet = false
    @State private var refreshTimer: Timer?
    @State private var navigateToSession: AgentSession?

    private var activeSessions: [AgentSession] {
        appState.agentSessions.filter { $0.running || $0.isIdle }
    }

    private var recentSessions: [AgentSession] {
        appState.agentSessions.filter { !$0.running && !$0.isIdle }.prefix(5).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                // Machine status bar
                if let sys = appState.systemInfo {
                    Section {
                        machineBar(sys)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // Active sessions
                if !activeSessions.isEmpty {
                    Section {
                        ForEach(activeSessions) { session in
                            NavigationLink(value: session) {
                                ActiveSessionCard(session: session)
                            }
                        }
                    } header: {
                        Label("Active Projects", systemImage: "bolt.fill")
                            .foregroundStyle(.green)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // Quick actions
                Section {
                    quickActions
                } header: {
                    Label("Quick Actions", systemImage: "sparkles")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // Recent
                if !recentSessions.isEmpty {
                    Section("Recent") {
                        ForEach(recentSessions) { session in
                            NavigationLink(value: session) {
                                RecentSessionRow(session: session)
                            }
                        }
                    }
                }

                // Empty state
                if appState.agentSessions.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "brain")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No active projects")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Start a task to get an AI agent working on a project")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("KMac Pilot")
            .navigationDestination(for: AgentSession.self) { session in
                ProjectDetailView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showTaskSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        Button {
                            Task { await appState.refreshAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showTaskSheet) {
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

    private func machineBar(_ sys: SystemInfo) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(sys.hostname)
                    .font(.caption.bold())
            }
            Spacer()
            Text(sys.uptime)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Load: \(sys.load)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ActionButton(icon: "play.fill", label: "New Task", color: .blue) {
                showTaskSheet = true
            }
            ActionButton(icon: "terminal", label: "Terminal", color: .green) {
                appState.showTerminal = true
            }
            ActionButton(icon: "shippingbox", label: "Docker", color: .cyan) {
                appState.showDocker = true
            }
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { await appState.refreshStatus() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Active session card

struct ActiveSessionCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.project)
                    .font(.headline)
                Spacer()
                Text(session.agentLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
            }

            Text(session.task)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label("\(session.outputLines) lines", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }
}

// MARK: - Recent session row

struct RecentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.project)
                    .font(.subheadline.bold())
                Text(session.task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.status)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
                Text(session.agentLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch session.status {
        case "completed": return .blue
        case "failed": return .red
        case "stopped": return .orange
        default: return .gray
        }
    }
}

// MARK: - Reusable components

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

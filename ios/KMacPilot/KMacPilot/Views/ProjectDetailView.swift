import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: AgentSession

    @State private var currentSession: AgentSession?
    @State private var selectedTab = 0
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Project header
            projectHeader

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Label("Terminal", systemImage: "terminal").tag(0)
                Label("Files", systemImage: "doc.text").tag(1)
                Label("Git", systemImage: "arrow.triangle.branch").tag(2)
                Label("Shell", systemImage: "chevron.left.forwardslash.chevron.right").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Tab content
            switch selectedTab {
            case 0: SessionTerminalTab(sessionId: session.id)
            case 1: ProjectFilesTab(projectDir: session.dir, projectName: session.project)
            case 2: ProjectGitTab(projectName: session.project)
            case 3: ProjectShellTab(projectName: session.project)
            default: EmptyView()
            }
        }
        .navigationTitle(session.project)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if let s = currentSession, s.running {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private var projectHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                    Text(session.agentLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                }
                Text(session.task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let s = currentSession, s.running {
                Button {
                    stopSession()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    Button {
                        approveChanges()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                    Button {
                        rejectChanges()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        guard let s = currentSession else { return .gray }
        if s.running { return .green }
        switch s.status {
        case "completed": return .blue
        case "failed": return .red
        case "stopped": return .orange
        default: return .gray
        }
    }

    private func stopSession() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                _ = try await api.stopSession(id: session.id)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func approveChanges() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                _ = try await api.approve()
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectChanges() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                _ = try await api.reject()
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func startPolling() {
        refreshSession()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            refreshSession()
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshSession() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                currentSession = try await api.sessionDetail(id: session.id)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Terminal tab (agent conversation)

struct SessionTerminalTab: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    @State private var outputLines: [String] = []
    @State private var askText = ""
    @State private var isAsking = false
    @State private var refreshTimer: Timer?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                                .id(idx)
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

            // Follow-up input
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                    .font(.caption)

                TextField("Ask a follow-up...", text: $askText)
                    .font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
                    .onSubmit { askFollowUp() }

                if isAsking {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { askFollowUp() } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.purple)
                    }
                    .disabled(askText.isEmpty)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear { loadOutput(); startPolling() }
        .onDisappear { stopPolling() }
    }

    private func loadOutput() {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let output = try await api.sessionOutput(id: sessionId, tail: 500)
                outputLines = output.lines
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func askFollowUp() {
        let q = askText
        guard !q.isEmpty else { return }
        askText = ""
        isAsking = true
        Task { @MainActor in
            defer {
                isAsking = false
                isInputFocused = true
            }
            guard let api = appState.api else { return }
            do {
                let result = try await api.askSession(id: sessionId, question: q)
                if let output = result.output {
                    outputLines.append(contentsOf: ["", "── \(q) ──", ""])
                    outputLines.append(contentsOf: output.components(separatedBy: "\n"))
                }
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                guard let api = appState.api else { return }
                do {
                    let output = try await api.sessionOutput(id: sessionId, tail: 500)
                    if output.total > outputLines.count {
                        outputLines = output.lines
                    }
                } catch {
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Files tab (browse project directory)

struct ProjectFilesTab: View {
    @EnvironmentObject var appState: AppState
    let projectDir: String
    let projectName: String

    @State private var items: [BrowseItem] = []
    @State private var currentPath: String = ""
    @State private var pathHistory: [String] = []
    @State private var isLoading = false
    @State private var selectedFile: FileContent?

    var body: some View {
        VStack(spacing: 0) {
            if currentPath != projectDir {
                Button {
                    goUp()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                        Spacer()
                        Text(currentPath.replacingOccurrences(of: projectDir + "/", with: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider()
            }

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List {
                    let folders = items.filter { $0.isDir }
                    let files = items.filter { !$0.isDir }

                    ForEach(folders) { item in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.yellow)
                                .frame(width: 24)
                            Text(item.name).font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(item.path) }
                    }

                    ForEach(files) { item in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(item.name).font(.subheadline)
                            Spacer()
                            if let size = item.size {
                                Text(formatSize(size))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { loadFile(item.path) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selectedFile) { file in
            FileContentView(file: file)
        }
        .onAppear { loadDir(projectDir) }
    }

    private func loadDir(_ path: String) {
        isLoading = true
        currentPath = path
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let result = try await api.browse(path: path)
                items = result.items ?? []
            } catch {
                items = []
                appState.errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func navigateTo(_ path: String) {
        pathHistory.append(currentPath)
        loadDir(path)
    }

    private func goUp() {
        if let prev = pathHistory.popLast() {
            loadDir(prev)
        }
    }

    private func loadFile(_ path: String) {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                selectedFile = try await api.readFileAbs(path: path)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - Git tab

struct ProjectGitTab: View {
    @EnvironmentObject var appState: AppState
    let projectName: String

    @State private var commits: [GitCommit] = []
    @State private var diff: DiffResult?
    @State private var isLoading = false

    var body: some View {
        List {
            if let diff, diff.hasChanges {
                Section("Uncommitted Changes") {
                    ForEach(diff.filesChanged, id: \.self) { file in
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.orange)
                            Text(file)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    ForEach(diff.untracked, id: \.self) { file in
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text(file)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            Section("Recent Commits") {
                if commits.isEmpty && !isLoading {
                    Text("No commits")
                        .foregroundStyle(.secondary)
                }
                ForEach(commits) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.message)
                            .font(.subheadline)
                            .lineLimit(2)
                        HStack {
                            Text(String(commit.hash.prefix(7)))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.blue)
                            Text(commit.time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .onAppear { loadGit() }
    }

    private func loadGit() {
        isLoading = true
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                async let d = api.diff()
                async let c = api.gitLog(project: projectName)
                diff = try await d
                commits = try await c
            } catch {
                appState.errorMessage = error.localizedDescription
                diff = nil
                commits = []
            }
            isLoading = false
        }
    }
}

// MARK: - Shell tab

struct ProjectShellTab: View {
    @EnvironmentObject var appState: AppState
    let projectName: String

    @State private var command = ""
    @State private var history: [(cmd: String, output: String, exitCode: Int)] = []
    @State private var isRunning = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                .onChange(of: history.count) { _, newCount in
                    guard newCount > 0 else { return }
                    withAnimation { proxy.scrollTo(newCount - 1) }
                }
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(.blue)

                TextField("command", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
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
        .onAppear { isInputFocused = true }
    }

    private func runCommand() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        command = ""
        isRunning = true
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let result = try await api.run(command: cmd, project: projectName)
                history.append((cmd: cmd, output: result.output ?? result.error ?? "(no output)", exitCode: result.exitCode ?? -1))
            } catch {
                history.append((cmd: cmd, output: error.localizedDescription, exitCode: -1))
            }
            isRunning = false
            isInputFocused = true
        }
    }
}

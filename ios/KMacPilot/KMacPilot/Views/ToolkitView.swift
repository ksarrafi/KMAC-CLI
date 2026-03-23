import SwiftUI

struct ToolkitView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    Text("Docker").tag(0)
                    Text("Services").tag(1)
                    Text("System").tag(2)
                    Text("Network").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case 0: DockerTab()
                case 1: ServicesTab()
                case 2: SystemTab()
                case 3: NetworkTab()
                default: EmptyView()
                }
            }
            .navigationTitle("Toolkit")
        }
    }
}

// MARK: - Docker

struct DockerTab: View {
    @EnvironmentObject var appState: AppState
    @State private var containers: [DockerContainer] = []
    @State private var dockerAvailable = false
    @State private var isLoading = true
    @State private var showLogs: (String, String)? = nil

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if !dockerAvailable {
                ContentUnavailableView("Docker Not Found", systemImage: "shippingbox",
                    description: Text("Docker is not installed or not running"))
            } else {
                List {
                    let running = containers.filter { $0.isRunning }
                    let stopped = containers.filter { !$0.isRunning }

                    if !running.isEmpty {
                        Section("Running") {
                            ForEach(running) { c in
                                ContainerRow(container: c, onAction: { performAction(c.containerId, $0) },
                                             onLogs: { loadLogs(c.containerId, c.name) })
                            }
                        }
                    }

                    if !stopped.isEmpty {
                        Section("Stopped") {
                            ForEach(stopped) { c in
                                ContainerRow(container: c, onAction: { performAction(c.containerId, $0) },
                                             onLogs: { loadLogs(c.containerId, c.name) })
                            }
                        }
                    }

                    if containers.isEmpty {
                        Text("No containers")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { showLogs.map { LogSheet(name: $0.0, logs: $0.1) } },
            set: { _ in showLogs = nil }
        )) { sheet in
            NavigationStack {
                ScrollView {
                    Text(sheet.logs)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black)
                .navigationTitle(sheet.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showLogs = nil }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        do {
            dockerAvailable = try await api.dockerStatus()
            if dockerAvailable {
                containers = try await api.dockerContainers()
            } else {
                containers = []
            }
        } catch {
            appState.errorMessage = error.localizedDescription
            dockerAvailable = false
            containers = []
        }
        isLoading = false
    }

    private func performAction(_ id: String, _ action: String) {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                _ = try await api.dockerAction(container: id, action: action)
                try await Task.sleep(for: .seconds(1))
            } catch {
                appState.errorMessage = error.localizedDescription
            }
            await load()
        }
    }

    private func loadLogs(_ id: String, _ name: String) {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let logs = try await api.dockerLogs(container: id)
                showLogs = (name, logs)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}

struct LogSheet: Identifiable {
    let id = UUID()
    let name: String
    let logs: String
}

struct ContainerRow: View {
    let container: DockerContainer
    let onAction: (String) -> Void
    let onLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(container.isRunning ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(container.name)
                    .font(.subheadline.bold())
                Spacer()
                Text(container.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(container.image)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if !container.ports.isEmpty {
                Text(container.ports)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                if container.isRunning {
                    Button("Stop") { onAction("stop") }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Button("Restart") { onAction("restart") }
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else {
                    Button("Start") { onAction("start") }
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Button("Remove") { onAction("remove") }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Logs") { onLogs() }
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Services

struct ServicesTab: View {
    @EnvironmentObject var appState: AppState
    @State private var devServices: [ServiceInfo] = []
    @State private var brewServices: [ServiceInfo] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else {
                Section("Dev Services") {
                    ForEach(devServices) { s in
                        HStack {
                            Circle()
                                .fill(s.isRunning ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(s.name)
                                .font(.subheadline)
                            Spacer()
                            Text(s.status)
                                .font(.caption)
                                .foregroundStyle(s.isRunning ? .green : .secondary)
                        }
                    }
                }

                if !brewServices.isEmpty {
                    Section("Homebrew Services") {
                        ForEach(brewServices) { s in
                            HStack {
                                Circle()
                                    .fill(s.isRunning ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(s.name)
                                    .font(.subheadline)
                                Spacer()
                                Text(s.status)
                                    .font(.caption)
                                    .foregroundStyle(s.isRunning ? .green : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        do {
            async let d = api.services()
            async let b = api.brewServices()
            devServices = try await d
            brewServices = try await b
        } catch {
            appState.errorMessage = error.localizedDescription
            devServices = []
            brewServices = []
        }
        isLoading = false
    }
}

// MARK: - System

struct SystemTab: View {
    @EnvironmentObject var appState: AppState
    @State private var disks: [DiskInfo] = []
    @State private var processes: [ProcessInfo] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else {
                Section("Disk Usage") {
                    ForEach(Array(disks.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.mount)
                                .font(.subheadline.bold())
                            HStack {
                                ProgressView(value: percentValue(d.percent), total: 100)
                                    .tint(percentValue(d.percent) > 80 ? .red : .blue)
                                Text(d.percent)
                                    .font(.caption.bold())
                            }
                            HStack {
                                Text("\(d.used) used")
                                Text("·")
                                Text("\(d.available) free")
                                Text("·")
                                Text("\(d.size) total")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Top Processes") {
                    ForEach(processes) { p in
                        HStack {
                            Text(p.command)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text("\(p.cpu)%")
                                .font(.caption.bold())
                                .foregroundStyle(Double(p.cpu) ?? 0 > 50 ? .red : .secondary)
                            Text("\(p.mem)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        do {
            async let d = api.disk()
            async let p = api.processes()
            disks = try await d
            processes = try await p
        } catch {
            appState.errorMessage = error.localizedDescription
            disks = []
            processes = []
        }
        isLoading = false
    }

    private func percentValue(_ str: String) -> Double {
        Double(str.replacingOccurrences(of: "%", with: "")) ?? 0
    }
}

// MARK: - Network

struct NetworkTab: View {
    @EnvironmentObject var appState: AppState
    @State private var networkInfo: NetworkInfo?
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if let net = networkInfo {
                Section("IP Addresses") {
                    HStack {
                        Text("Local IP")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(net.localIp.isEmpty ? "—" : net.localIp)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Public IP")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(net.publicIp.isEmpty ? "—" : net.publicIp)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if !net.listening.isEmpty {
                    Section("Listening Ports") {
                        ForEach(net.listening) { port in
                            HStack {
                                Text(port.process)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(port.address)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        do {
            networkInfo = try await api.network()
        } catch {
            appState.errorMessage = error.localizedDescription
            networkInfo = nil
        }
        isLoading = false
    }
}

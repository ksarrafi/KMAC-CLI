import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Label("Status", systemImage: "wifi")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appState.isConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(appState.isConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let sys = appState.systemInfo {
                        HStack {
                            Label("Host", systemImage: "desktopcomputer")
                            Spacer()
                            Text(sys.hostname)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Label("Server", systemImage: "link")
                        Spacer()
                        Text(appState.serverURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Section("AI Agent") {
                    if let sys = appState.systemInfo {
                        HStack {
                            Label("Active", systemImage: "brain")
                            Spacer()
                            Text(sys.agentLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Project Directories") {
                    if let sys = appState.systemInfo {
                        ForEach(sys.projectDirs.components(separatedBy: ","), id: \.self) { dir in
                            Label(dir.trimmingCharacters(in: .whitespaces), systemImage: "folder")
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        appState.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                }

                Section("About") {
                    HStack {
                        Text("KMac Pilot")
                        Spacer()
                        Text("v1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

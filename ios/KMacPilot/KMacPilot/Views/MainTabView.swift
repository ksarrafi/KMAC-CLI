import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            SessionsView()
                .tabItem {
                    Label("Tasks", systemImage: "brain")
                }

            FileBrowserView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            ToolkitView()
                .tabItem {
                    Label("Toolkit", systemImage: "wrench.and.screwdriver")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showTerminal) {
            NavigationStack {
                TerminalView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { appState.showTerminal = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $appState.showDocker) {
            NavigationStack {
                DockerTab()
                    .navigationTitle("Docker")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { appState.showDocker = false }
                        }
                    }
            }
        }
    }
}

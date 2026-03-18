import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showTaskSheet = false
    @State private var selectedForTask: Project?

    private var grouped: [(String, [Project])] {
        let filtered = appState.projects.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let dict = Dictionary(grouping: filtered, by: \.group)
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { group, projects in
                    Section(group) {
                        ForEach(projects) { project in
                            ProjectRow(project: project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedProject = project
                                    selectedForTask = project
                                    showTaskSheet = true
                                }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter projects")
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            guard let api = appState.api else { return }
                            appState.projects = try await api.projects()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showTaskSheet) {
                if let project = selectedForTask {
                    TaskStartSheet(preselectedProject: project.name)
                }
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            Image(systemName: project.isGit ? "externaldrive.connected.to.line.below" : "folder")
                .foregroundStyle(project.isGit ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body.bold())
                if let branch = project.branch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(branch)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

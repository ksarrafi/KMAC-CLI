import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var roots: [BrowseRoot] = []
    @State private var currentPath: String?
    @State private var currentLabel: String?
    @State private var parentPath: String?
    @State private var items: [BrowseItem] = []
    @State private var pathHistory: [String] = []
    @State private var isLoading = false
    @State private var selectedFile: FileContent?
    @State private var isGitRepo = false
    @State private var repoBranch: String?
    @State private var projectName: String?
    @State private var showTaskSheet = false
    @State private var selectedAgent = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading...")
                } else if currentPath == nil {
                    rootsView
                } else {
                    directoryView
                }
            }
            .navigationTitle(breadcrumb)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentPath != nil {
                        Button {
                            goUp()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if isGitRepo {
                            Button {
                                selectedAgent = "claude"
                                showTaskSheet = true
                            } label: {
                                Image(systemName: "brain")
                                    .foregroundStyle(.purple)
                            }
                        }
                        Button { refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(item: $selectedFile) { file in
                FileContentView(file: file)
            }
            .sheet(isPresented: $showTaskSheet) {
                if let name = projectName {
                    TaskStartSheet(preselectedProject: name, preselectedAgent: selectedAgent)
                }
            }
            .onAppear { loadRoots() }
        }
    }

    private var breadcrumb: String {
        guard let path = currentLabel else { return "Files" }
        let parts = path
            .replacingOccurrences(of: "~/", with: "")
            .components(separatedBy: "/")
            .filter { !$0.isEmpty }
        if parts.count <= 2 {
            return parts.joined(separator: " / ")
        }
        return parts.suffix(2).joined(separator: " / ")
    }

    // MARK: - Roots view

    private var rootsView: some View {
        List {
            Section("Project Directories") {
                ForEach(roots) { root in
                    Button { navigateTo(root.path) } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            Text(root.label)
                                .font(.body.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Directory listing

    private var directoryView: some View {
        List {
            if isGitRepo, let name = projectName {
                Section {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.blue)
                            Text(repoBranch ?? "—")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                selectedAgent = "claude"
                                showTaskSheet = true
                            } label: {
                                Label("Claude", systemImage: "brain")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.purple.opacity(0.15))
                                    .foregroundStyle(.purple)
                                    .cornerRadius(8)
                            }

                            Button {
                                selectedAgent = "cursor"
                                showTaskSheet = true
                            } label: {
                                Label("Cursor", systemImage: "cursorarrow.rays")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            let folders = items.filter { $0.isDir }
            let files = items.filter { !$0.isDir }

            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { item in
                        Button { navigateTo(item.path) } label: {
                            FolderRow(item: item)
                        }
                    }
                }
            }

            if !files.isEmpty {
                Section("Files") {
                    ForEach(files) { item in
                        Button { loadFile(item.path) } label: {
                            FileRow(item: item)
                        }
                    }
                }
            }

            if folders.isEmpty && files.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("No items in this directory"))
            }
        }
    }

    // MARK: - Navigation

    private func loadRoots() {
        guard roots.isEmpty else { return }
        isLoading = true
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                roots = try await api.browseRoots()
            } catch {}
            isLoading = false
        }
    }

    private func navigateTo(_ path: String) {
        if let cur = currentPath {
            pathHistory.append(cur)
        }
        loadDirectory(path)
    }

    private func goUp() {
        if let prev = pathHistory.popLast() {
            loadDirectory(prev)
        } else {
            currentPath = nil
            currentLabel = nil
            items = []
            isGitRepo = false
            repoBranch = nil
            projectName = nil
        }
    }

    private func loadDirectory(_ path: String) {
        isLoading = true
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let result = try await api.browse(path: path)
                currentPath = result.path
                currentLabel = result.label
                parentPath = result.parent
                items = result.items ?? []
                isGitRepo = result.isGit ?? false
                repoBranch = result.branch
                projectName = result.projectName
            } catch {
                items = []
                isGitRepo = false
            }
            isLoading = false
        }
    }

    private func refresh() {
        if let path = currentPath {
            loadDirectory(path)
        } else {
            roots = []
            loadRoots()
        }
    }

    private func loadFile(_ path: String) {
        Task { @MainActor in
            guard let api = appState.api else { return }
            do {
                let content = try await api.readFileAbs(path: path)
                selectedFile = content
            } catch {}
        }
    }
}

// MARK: - Row views

struct FolderRow: View {
    let item: BrowseItem

    var body: some View {
        HStack {
            Image(systemName: item.isGit == true ? "folder.fill.badge.gearshape" : "folder.fill")
                .foregroundStyle(item.isGit == true ? .blue : .yellow)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                if let branch = item.branch {
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
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct FileRow: View {
    let item: BrowseItem

    var body: some View {
        HStack {
            Image(systemName: iconForFile(item.name))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(item.name)
                .foregroundStyle(.primary)

            Spacer()

            if let size = item.size {
                Text(formatSize(size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "gearshape"
        case "md", "txt", "rst", "csv":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico":
            return "photo"
        case "sh", "bash", "zsh":
            return "terminal"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz":
            return "archivebox"
        case "mp4", "mov", "webm":
            return "film"
        case "html", "css", "scss":
            return "globe"
        default:
            return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

extension FileContent: @retroactive Identifiable {
    public var id: String { path ?? UUID().uuidString }
}

struct FileContentView: View {
    let file: FileContent
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                ScrollView(.vertical) {
                    if let content = file.content {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.9))
                            .padding()
                            .textSelection(.enabled)
                    } else if let error = file.error {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    }
                }
            }
            .background(Color.black)
            .navigationTitle(file.path?.components(separatedBy: "/").last ?? "File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let size = file.size {
                        Text(formatSize(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

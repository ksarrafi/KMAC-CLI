import Foundation

struct Project: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let branch: String?
    let isGit: Bool
    let group: String

    enum CodingKeys: String, CodingKey {
        case name, path, branch, group
        case isGit = "is_git"
    }
}

struct TaskInfo: Codable {
    let project: String?
    let dir: String?
    let task: String?
    let agent: String?
    let agentLabel: String?
    let started: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case project, dir, task, agent, started, status
        case agentLabel = "agent_label"
    }
}

struct TaskStatusResponse: Codable {
    let running: Bool
    let task: TaskInfo
    let outputLines: Int

    enum CodingKeys: String, CodingKey {
        case running, task
        case outputLines = "output_lines"
    }
}

struct SystemInfo: Codable {
    let hostname: String
    let uptime: String
    let load: String
    let agent: String
    let agentLabel: String
    let projectDirs: String

    enum CodingKeys: String, CodingKey {
        case hostname, uptime, load, agent
        case agentLabel = "agent_label"
        case projectDirs = "project_dirs"
    }
}

struct FileNode: Codable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let type: String
    let size: Int?
    let children: [FileNode]?
}

struct FileContent: Codable {
    let path: String?
    let content: String?
    let size: Int?
    let error: String?
    let `extension`: String?
}

struct DiffResult: Codable {
    let stat: String
    let fullDiff: String
    let untracked: [String]
    let filesChanged: [String]
    let hasChanges: Bool

    enum CodingKeys: String, CodingKey {
        case stat, untracked
        case fullDiff = "full_diff"
        case filesChanged = "files_changed"
        case hasChanges = "has_changes"
    }
}

struct GitCommit: Codable, Identifiable {
    var id: String { hash }
    let hash: String
    let message: String
    let time: String
}

struct RunResult: Codable {
    let output: String?
    let exitCode: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case output, error
        case exitCode = "exit_code"
    }
}

struct BrowseRoot: Codable, Identifiable {
    var id: String { path }
    let path: String
    let label: String
}

struct BrowseItem: Codable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let type: String
    let size: Int?
    let isGit: Bool?
    let branch: String?

    enum CodingKeys: String, CodingKey {
        case name, path, type, size, branch
        case isGit = "is_git"
    }

    var isDir: Bool { type == "dir" }
}

struct BrowseResult: Codable {
    let path: String?
    let label: String?
    let parent: String?
    let items: [BrowseItem]?
    let error: String?
    let isGit: Bool?
    let branch: String?
    let projectName: String?

    enum CodingKeys: String, CodingKey {
        case path, label, parent, items, error, branch
        case isGit = "is_git"
        case projectName = "project_name"
    }
}

// Sessions (multi-agent)

struct AgentSession: Codable, Identifiable, Hashable {
    let id: String
    let project: String
    let dir: String
    let task: String
    let agent: String
    let agentLabel: String
    let status: String
    let started: String
    let running: Bool
    let outputLines: Int
    let pid: Int?

    enum CodingKeys: String, CodingKey {
        case id, project, dir, task, agent, status, started, running, pid
        case agentLabel = "agent_label"
        case outputLines = "output_lines"
    }

    var statusColor: String {
        switch status {
        case "running": return "green"
        case "idle": return "purple"
        case "completed": return "blue"
        case "failed": return "red"
        case "stopped": return "orange"
        default: return "gray"
        }
    }

    var isIdle: Bool { status == "idle" }
}

struct SessionsResponse: Codable {
    let sessions: [AgentSession]
    let running: Int
    let total: Int
}

// Docker

struct DockerContainer: Codable, Identifiable {
    var id: String { containerId }
    let containerId: String
    let name: String
    let image: String
    let status: String
    let state: String
    let ports: String

    enum CodingKeys: String, CodingKey {
        case containerId = "id"
        case name, image, status, state, ports
    }

    var isRunning: Bool { state == "running" }
}

struct DockerImage: Codable, Identifiable {
    var id: String { imageId }
    let imageId: String
    let repo: String
    let tag: String
    let size: String
    let created: String

    enum CodingKeys: String, CodingKey {
        case imageId = "id"
        case repo, tag, size, created
    }
}

// System / Toolkit

struct DiskInfo: Codable {
    let filesystem: String
    let size: String
    let used: String
    let available: String
    let percent: String
    let mount: String
}

struct ProcessInfo: Codable, Identifiable {
    var id: String { pid }
    let user: String
    let pid: String
    let cpu: String
    let mem: String
    let command: String
}

struct NetworkInfo: Codable {
    let localIp: String
    let publicIp: String
    let listening: [ListeningPort]

    enum CodingKeys: String, CodingKey {
        case localIp = "local_ip"
        case publicIp = "public_ip"
        case listening
    }
}

struct ListeningPort: Codable, Identifiable {
    var id: String { "\(process)-\(pid)-\(address)" }
    let process: String
    let pid: String
    let address: String
}

struct ServiceInfo: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let user: String?

    var isRunning: Bool { status == "running" || status == "started" }
}

// WebSocket events
enum WSEvent {
    case connected(running: Bool, task: TaskInfo?)
    case output(line: String)
    case taskStarted(project: String, agent: String, prompt: String)
    case taskFinished(status: String, exitCode: Int, project: String, lines: Int)
    case taskStopped(project: String)
    case unknown
}

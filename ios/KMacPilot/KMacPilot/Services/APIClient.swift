import Foundation

actor APIClient {
    let baseURL: String
    let token: String

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
    }

    // MARK: - Generic request

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(http.statusCode, msg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await request("GET", path: path, query: query)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any] = [:]) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    // MARK: - System

    func ping() async throws -> Bool {
        struct PingResponse: Decodable { let ok: Bool }
        let r: PingResponse = try await get("/api/ping")
        return r.ok
    }

    func system() async throws -> SystemInfo {
        try await get("/api/system")
    }

    // MARK: - Projects

    struct ProjectsResponse: Decodable { let projects: [Project] }

    func projects(filter: String = "") async throws -> [Project] {
        let r: ProjectsResponse = try await get("/api/projects", query: filter.isEmpty ? [:] : ["filter": filter])
        return r.projects
    }

    // MARK: - Files

    struct TreeResponse: Decodable { let tree: [FileNode] }

    func fileTree(project: String, path: String = "") async throws -> [FileNode] {
        let r: TreeResponse = try await get("/api/files/tree", query: ["project": project, "path": path])
        return r.tree
    }

    func fileRead(project: String, path: String) async throws -> FileContent {
        try await get("/api/files/read", query: ["project": project, "path": path])
    }

    // Browse filesystem
    struct BrowseRootsResponse: Decodable { let roots: [BrowseRoot] }

    func browseRoots() async throws -> [BrowseRoot] {
        let r: BrowseRootsResponse = try await get("/api/browse/roots")
        return r.roots
    }

    func browse(path: String) async throws -> BrowseResult {
        try await get("/api/browse", query: ["path": path])
    }

    func readFileAbs(path: String) async throws -> FileContent {
        try await get("/api/files/abs", query: ["path": path])
    }

    // MARK: - Git

    func diff() async throws -> DiffResult {
        try await get("/api/git/diff")
    }

    struct ApproveResponse: Decodable { let ok: Bool?; let hash: String?; let error: String? }

    func approve(message: String = "") async throws -> ApproveResponse {
        try await post("/api/git/approve", body: ["message": message])
    }

    struct SimpleResponse: Decodable { let ok: Bool? }

    func reject() async throws -> SimpleResponse {
        try await post("/api/git/reject")
    }

    struct GitLogResponse: Decodable { let commits: [GitCommit] }

    func gitLog(project: String = "", count: Int = 20) async throws -> [GitCommit] {
        let r: GitLogResponse = try await get("/api/git/log", query: ["project": project, "count": "\(count)"])
        return r.commits
    }

    // MARK: - Sessions (multi-agent)

    func sessions() async throws -> SessionsResponse {
        try await get("/api/sessions")
    }

    struct SessionCreateResponse: Decodable { let ok: Bool?; let error: String?; let session: AgentSession? }

    func createSession(project: String, prompt: String, agent: String = "") async throws -> SessionCreateResponse {
        var body: [String: Any] = ["project": project, "prompt": prompt]
        if !agent.isEmpty { body["agent"] = agent }
        return try await post("/api/sessions", body: body)
    }

    func sessionDetail(id: String) async throws -> AgentSession {
        try await get("/api/sessions/\(id)")
    }

    func sessionOutput(id: String, tail: Int = 200) async throws -> OutputResponse {
        try await get("/api/sessions/\(id)/output", query: ["tail": "\(tail)"])
    }

    func stopSession(id: String) async throws -> SimpleResponse {
        try await post("/api/sessions/\(id)/stop")
    }

    func deleteSession(id: String) async throws -> SimpleResponse {
        try await request("DELETE", path: "/api/sessions/\(id)")
    }

    func askSession(id: String, question: String) async throws -> AskResponse {
        try await post("/api/sessions/\(id)/ask", body: ["question": question])
    }

    func sendMessage(id: String, message: String) async throws -> SimpleResponse {
        try await post("/api/sessions/\(id)/send", body: ["message": message])
    }

    // MARK: - Task (legacy)

    struct TaskStartResponse: Decodable { let ok: Bool?; let error: String?; let project: String?; let agent: String? }

    func startTask(project: String, prompt: String, agent: String = "") async throws -> TaskStartResponse {
        var body: [String: Any] = ["project": project, "prompt": prompt]
        if !agent.isEmpty { body["agent"] = agent }
        return try await post("/api/task", body: body)
    }

    func taskStatus() async throws -> TaskStatusResponse {
        try await get("/api/task/status")
    }

    func stopTask() async throws -> SimpleResponse {
        try await post("/api/task/stop")
    }

    struct OutputResponse: Decodable { let lines: [String]; let total: Int; let session_id: String? }

    func taskOutput(tail: Int = 50) async throws -> OutputResponse {
        try await get("/api/task/output", query: ["tail": "\(tail)"])
    }

    // MARK: - Ask

    struct AskResponse: Decodable { let ok: Bool?; let output: String?; let error: String? }

    func ask(question: String) async throws -> AskResponse {
        try await post("/api/ask", body: ["question": question])
    }

    // MARK: - Run

    func run(command: String, project: String = "") async throws -> RunResult {
        try await post("/api/run", body: ["command": command, "project": project])
    }

    // MARK: - Docker

    struct DockerStatusResponse: Decodable { let available: Bool }
    func dockerStatus() async throws -> Bool {
        let r: DockerStatusResponse = try await get("/api/docker/status")
        return r.available
    }

    struct ContainersResponse: Decodable { let containers: [DockerContainer] }
    func dockerContainers(all: Bool = true) async throws -> [DockerContainer] {
        let r: ContainersResponse = try await get("/api/docker/containers", query: ["all": all ? "true" : "false"])
        return r.containers
    }

    struct ImagesResponse: Decodable { let images: [DockerImage] }
    func dockerImages() async throws -> [DockerImage] {
        let r: ImagesResponse = try await get("/api/docker/images")
        return r.images
    }

    func dockerAction(container: String, action: String) async throws -> SimpleResponse {
        try await post("/api/docker/action", body: ["container": container, "action": action])
    }

    struct DockerLogsResponse: Decodable { let logs: String; let container: String }
    func dockerLogs(container: String, tail: Int = 100) async throws -> String {
        let r: DockerLogsResponse = try await get("/api/docker/logs", query: ["container": container, "tail": "\(tail)"])
        return r.logs
    }

    // MARK: - System / Toolkit

    struct DiskResponse: Decodable { let disks: [DiskInfo] }
    func disk() async throws -> [DiskInfo] {
        let r: DiskResponse = try await get("/api/system/disk")
        return r.disks
    }

    struct ProcessesResponse: Decodable { let processes: [ProcessInfo] }
    func processes() async throws -> [ProcessInfo] {
        let r: ProcessesResponse = try await get("/api/system/processes")
        return r.processes
    }

    func network() async throws -> NetworkInfo {
        try await get("/api/system/network")
    }

    struct ServicesResponse: Decodable { let services: [ServiceInfo] }
    func services() async throws -> [ServiceInfo] {
        let r: ServicesResponse = try await get("/api/system/services")
        return r.services
    }

    func brewServices() async throws -> [ServiceInfo] {
        let r: ServicesResponse = try await get("/api/system/brew")
        return r.services
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var isConnected = false
    @Published var serverURL: String = ""
    @Published var token: String = ""

    @Published var systemInfo: SystemInfo?
    @Published var taskStatus: TaskStatusResponse?
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?

    @Published var agentSessions: [AgentSession] = []

    @Published var showTerminal = false
    @Published var showDocker = false

    @Published var isLoading = false
    @Published var errorMessage: String?

    private(set) var api: APIClient?
    let ws = WebSocketClient()

    private let urlKey = "kmac_server_url"
    private let tokenKey = "kmac_server_token"

    init() {
        serverURL = UserDefaults.standard.string(forKey: urlKey) ?? ""
        token = UserDefaults.standard.string(forKey: tokenKey) ?? ""

        if !serverURL.isEmpty && !token.isEmpty {
            Task { await connect() }
        }
    }

    func connect() async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }

        let url = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        let client = APIClient(baseURL: url, token: token)

        isLoading = true
        errorMessage = nil

        do {
            let ok = try await client.ping()
            guard ok else {
                errorMessage = "Server responded but ping failed"
                isLoading = false
                return
            }

            self.api = client
            self.isConnected = true

            UserDefaults.standard.set(url, forKey: urlKey)
            UserDefaults.standard.set(token, forKey: tokenKey)

            ws.connect(baseURL: url, token: token)

            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func disconnect() {
        ws.disconnect()
        api = nil
        isConnected = false
        systemInfo = nil
        taskStatus = nil
        projects = []
        agentSessions = []
        selectedProject = nil
        errorMessage = nil
    }

    func refreshAll() async {
        guard let api else { return }
        async let sys = api.system()
        async let status = api.taskStatus()
        async let projs = api.projects()
        async let sess = api.sessions()

        do {
            systemInfo = try await sys
            taskStatus = try await status
            projects = try await projs
            agentSessions = try await sess.sessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshStatus() async {
        guard let api else { return }
        do {
            taskStatus = try await api.taskStatus()
            agentSessions = try await api.sessions().sessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

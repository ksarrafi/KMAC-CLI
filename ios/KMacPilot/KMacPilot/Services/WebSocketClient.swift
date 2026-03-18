import Foundation

@Observable
class WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private(set) var isConnected = false
    private(set) var outputLines: [String] = []
    private(set) var sessionOutputs: [String: [String]] = [:]
    private(set) var lastEvent: WSEvent?

    var onEvent: ((WSEvent) -> Void)?

    func connect(baseURL: String, token: String) {
        let wsURL = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        var components = URLComponents(string: "\(wsURL)/ws")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { return }

        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        listen()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default:
                    break
                }
                self.listen()
            case .failure:
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        let sessionId = json["session_id"] as? String

        let event: WSEvent
        switch type {
        case "connected":
            DispatchQueue.main.async { self.isConnected = true }
            let count = json["running_count"] as? Int ?? 0
            event = .connected(running: count > 0, task: nil)

        case "output":
            let line = json["line"] as? String ?? ""
            DispatchQueue.main.async {
                self.outputLines.append(line)
                if let sid = sessionId {
                    var lines = self.sessionOutputs[sid, default: []]
                    lines.append(line)
                    self.sessionOutputs[sid] = lines
                }
            }
            event = .output(line: line)

        case "session_created":
            event = .taskStarted(
                project: json["project"] as? String ?? "",
                agent: json["agent"] as? String ?? "",
                prompt: json["prompt"] as? String ?? ""
            )

        case "session_finished":
            event = .taskFinished(
                status: json["status"] as? String ?? "",
                exitCode: json["exit_code"] as? Int ?? -1,
                project: json["project"] as? String ?? "",
                lines: json["lines"] as? Int ?? 0
            )

        case "session_stopped":
            event = .taskStopped(project: json["project"] as? String ?? "")

        // Legacy fallbacks
        case "task_started":
            event = .taskStarted(
                project: json["project"] as? String ?? "",
                agent: json["agent"] as? String ?? "",
                prompt: json["prompt"] as? String ?? ""
            )

        case "task_finished":
            event = .taskFinished(
                status: json["status"] as? String ?? "",
                exitCode: json["exit_code"] as? Int ?? -1,
                project: json["project"] as? String ?? "",
                lines: json["lines"] as? Int ?? 0
            )

        case "task_stopped":
            event = .taskStopped(project: json["project"] as? String ?? "")

        default:
            event = .unknown
        }

        DispatchQueue.main.async {
            self.lastEvent = event
            self.onEvent?(event)
        }
    }

    func clearOutput() {
        outputLines = []
    }

    func outputForSession(_ id: String) -> [String] {
        sessionOutputs[id] ?? []
    }
}

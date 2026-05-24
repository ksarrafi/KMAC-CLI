import Foundation

public class ClaudeAPI: @unchecked Sendable {
    private let apiKey: String
    private let apiEndpoint = "https://api.anthropic.com/v1/messages"
    private let modelId: String

    // MARK: - Initialization

    public init() throws {
        self.apiKey = try Self.loadAPIKey()
        // Overridable so the model can be bumped without a rebuild.
        self.modelId = ProcessInfo.processInfo.environment["KMAC_CLAUDE_MODEL"] ?? "claude-sonnet-4-6"
    }
    
    /// Persona shared by the CLI and the GUI. Forces macOS-specific, concise,
    /// runnable answers so the response can be turned into executable fixes.
    static let systemPreamble = """
    You are KMac, a macOS system-health assistant running ON the user's Mac (Apple Silicon/Intel, zsh, Homebrew likely installed). You have a live system snapshot below.

    Rules:
    - The OS is macOS. NEVER suggest Linux tools (apt, yum, dnf, journalctl, systemctl). Use macOS/BSD tools and Homebrew (brew cleanup), and macOS paths (~/Library/Caches, ~/Library/Developer/Xcode/DerivedData, ~/Downloads, /private/var/folders).
    - Be concise. Lead with the 2-3 highest-impact actions for the reported issue.
    - For every fix you recommend, output the exact command in its own ```bash code block so it can be run directly. One command (or short pipeline) per block.
    - Prefer safe, reversible commands. Never include destructive commands (rm -rf of broad paths, disk erase, sudo rm of system dirs). If something is risky, say so and give a safer inspection command first (e.g. du -sh before deleting).
    - Tailor advice to the actual numbers in the snapshot; don't give generic checklists.
    """

    // MARK: - Public Methods

    /// Streams a response from Claude API for the given query
    /// Returns an async sequence of response chunks
    public func askClaude(
        query: String,
        systemContext: String
    ) -> AsyncStream<String> {
        let requestBody = ClaudeAPIRequest(
            model: modelId,
            max_tokens: 2048,
            system: Self.systemPreamble + "\n\n" + systemContext,
            messages: [
                ClaudeMessage(role: "user", content: query)
            ],
            stream: true
        )

        let encoder = JSONEncoder()
        guard let requestData = try? encoder.encode(requestBody) else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = requestData

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        continuation.yield("[API error \(http.statusCode)] \(body)")
                        continuation.finish()
                        return
                    }

                    // Use the UTF-8-aware line sequence; decoding byte-by-byte as
                    // Unicode scalars (the old approach) mangles multi-byte chars
                    // like emoji into mojibake.
                    for try await rawLine in bytes.lines {
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        guard line.hasPrefix("data: ") else { continue }
                        let dataString = String(line.dropFirst(6))
                        guard let data = dataString.data(using: .utf8) else { continue }
                        if let streamResponse = try? JSONDecoder().decode(ClaudeStreamResponse.self, from: data),
                           let text = streamResponse.delta?.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield("[Network error] \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
    
    /// Parses Claude's response to extract suggested fixes
    /// Looks for bash code blocks in markdown format
    public func parseSuggestedFixes(response: String) -> [SuggestedFix] {
        var fixes: [SuggestedFix] = []
        
        let lines = response.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        
        while i < lines.count {
            let line = String(lines[i])
            
            // Look for markdown code block markers
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```bash") ||
               line.trimmingCharacters(in: .whitespaces).hasPrefix("```sh") {
                i += 1
                var command = ""
                
                // Collect all lines until closing ```
                while i < lines.count {
                    let currentLine = String(lines[i])
                    if currentLine.trimmingCharacters(in: .whitespaces) == "```" {
                        break
                    }
                    if !command.isEmpty {
                        command += "\n"
                    }
                    command += currentLine
                    i += 1
                }
                
                // Extract title and description from preceding text
                var title = "Fix"
                var description = "Apply this fix"
                var severity = "medium"
                
                // Look backwards for title patterns
                for j in stride(from: i - 1, through: 0, by: -1) {
                    let prevLine = String(lines[j]).trimmingCharacters(in: .whitespaces)
                    
                    if prevLine.isEmpty {
                        continue
                    }
                    
                    if prevLine.hasPrefix("##") {
                        title = prevLine.replacingOccurrences(of: "##", with: "").trimmingCharacters(in: .whitespaces)
                        break
                    } else if prevLine.hasPrefix("#") {
                        title = prevLine.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                        break
                    } else if !prevLine.hasPrefix("-") && !prevLine.hasPrefix("*") && !prevLine.hasPrefix("`") {
                        description = prevLine
                        break
                    }
                }
                
                // Determine severity from description
                if description.lowercased().contains("critical") ||
                   description.lowercased().contains("urgent") {
                    severity = "critical"
                } else if description.lowercased().contains("warning") {
                    severity = "warning"
                }
                
                let fix = SuggestedFix(
                    title: title,
                    description: description,
                    command: command.trimmingCharacters(in: .whitespaces),
                    severity: severity
                )
                fixes.append(fix)
            }
            
            i += 1
        }
        
        return fixes
    }
    
    // MARK: - Private Methods
    
    /// Resolves the Claude API key, in order:
    /// 1. CLAUDE_API_KEY / ANTHROPIC_API_KEY environment variables
    /// 2. The KMac vault (key `kmac:claude-api-key`, overridable via env)
    /// 3. The legacy file ~/Library/Application Support/Claude/api.key
    private static func loadAPIKey() throws -> String {
        let env = ProcessInfo.processInfo.environment
        for name in ["CLAUDE_API_KEY", "ANTHROPIC_API_KEY"] {
            if let v = env[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               isPlausibleKey(v) {
                return v
            }
        }

        // Vault is the source of truth; only a real-looking env var overrides it,
        // so placeholders like "your-api-key-here" don't shadow the vault.
        if let v = loadFromVault(), !v.isEmpty {
            return v
        }

        let fileManager = FileManager.default
        let expandedPath = ("~/Library/Application Support/Claude/api.key" as NSString).expandingTildeInPath
        if let keyData = fileManager.contents(atPath: expandedPath),
           let keyString = String(data: keyData, encoding: .utf8) {
            let trimmedKey = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                return trimmedKey
            }
        }

        throw ClaudeAPIError.missingAPIKey
    }

    /// True only for values shaped like a real Anthropic key, so common
    /// placeholders (your-api-key-here, changeme, empty) are rejected.
    private static func isPlausibleKey(_ v: String) -> Bool {
        v.hasPrefix("sk-") && v.count >= 20
    }

    /// Reads the key from the KMac vault by sourcing `_vault.sh` and calling its
    /// `vault_get` function, so the secret never lands in argv or this process's
    /// environment. Returns nil if the vault or key cannot be found.
    private static func loadFromVault() -> String? {
        let env = ProcessInfo.processInfo.environment
        let keyName = env["KMAC_VAULT_KEY"] ?? "kmac:claude-api-key"

        let fm = FileManager.default
        var dirs: [String] = []
        if let override = env["KMAC_VAULT_DIR"], !override.isEmpty { dirs.append(override) }
        let cwd = fm.currentDirectoryPath
        dirs += [cwd + "/scripts", cwd + "/../scripts"]
        if let home = env["HOME"] {
            dirs.append(home + "/Projects/Utilities/KMac-CLI/scripts")
        }
        // Walk up from the running executable looking for a sibling scripts/ dir.
        var exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            dirs.append(exeDir.appendingPathComponent("scripts").path)
            exeDir.deleteLastPathComponent()
        }

        guard let scriptsDir = dirs.first(where: { fm.fileExists(atPath: $0 + "/_vault.sh") }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source \"$0/_vault.sh\" >/dev/null 2>&1; vault_get \"$1\"", scriptsDir, keyName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        } catch {
            return nil
        }
    }
}

// MARK: - Support Types

public enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case networkError(String)
    case invalidResponse
    case decodingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API key not found. Set CLAUDE_API_KEY, store it in the KMac vault as 'kmac:claude-api-key' (./scripts/vault set), or place it in ~/Library/Application Support/Claude/api.key"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

// MARK: - API Request/Response Structures

private struct ClaudeAPIRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeStreamResponse: Codable {
    let type: String?
    let delta: ClaudeDelta?
    let message: ClaudeMessage?
    
    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case message
    }
}

private struct ClaudeDelta: Codable {
    let type: String?
    let text: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}
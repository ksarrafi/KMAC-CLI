import Foundation

public class ClaudeAPI: @unchecked Sendable {
    private let apiKey: String
    private let apiEndpoint = "https://api.anthropic.com/v1/messages"
    private let modelId = "claude-3-5-sonnet-20241022"
    
    // MARK: - Initialization
    
    public init() throws {
        self.apiKey = try Self.loadAPIKey()
    }
    
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
            system: systemContext,
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
                        for try await byte in bytes {
                            body.append(Character(UnicodeScalar(byte)))
                        }
                        continuation.yield("[API error \(http.statusCode)] \(body)")
                        continuation.finish()
                        return
                    }

                    var buffer = ""

                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))
                        if buffer.hasSuffix("\n") {
                            let line = buffer.trimmingCharacters(in: .whitespaces)
                            buffer = ""

                            if !line.isEmpty && !line.hasPrefix(":") {
                                if line.hasPrefix("data: ") {
                                    let dataString = String(line.dropFirst(6))
                                    if let data = dataString.data(using: .utf8) {
                                        do {
                                            let streamResponse = try JSONDecoder().decode(ClaudeStreamResponse.self, from: data)
                                            if let delta = streamResponse.delta,
                                               let text = delta.text {
                                                continuation.yield(text)
                                            }
                                        } catch {
                                            // Skip parsing errors
                                        }
                                    }
                                }
                            }
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
    
    /// Loads the Claude API key from environment or file
    private static func loadAPIKey() throws -> String {
        // First, check environment variable
        if let envKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        
        // Then, check default file location
        let fileManager = FileManager.default
        let defaultKeyPath = "~/Library/Application Support/Claude/api.key"
        let expandedPath = (defaultKeyPath as NSString).expandingTildeInPath
        
        if fileManager.fileExists(atPath: expandedPath),
           let keyData = fileManager.contents(atPath: expandedPath),
           let keyString = String(data: keyData, encoding: .utf8) {
            let trimmedKey = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                return trimmedKey
            }
        }
        
        throw ClaudeAPIError.missingAPIKey
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
            return "Claude API key not found. Set CLAUDE_API_KEY environment variable or place key in ~/Library/Application Support/Claude/api.key"
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
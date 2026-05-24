import Foundation

public struct FixExecutor {
    
    // MARK: - Constants
    
    private static let commandTimeout: TimeInterval = 30.0
    
    // MARK: - Public Methods
    
    /// Executes a shell command and returns its output
    /// - Parameter command: The shell command to execute
    /// - Returns: The stdout output from the command
    /// - Throws: FixExecutionError if command fails or times out
    public static func executeCommand(_ command: String, timeout: TimeInterval = 30) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try executeCommandSync(command, timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Checks whether a fix's command is syntactically valid WITHOUT running it.
    /// Uses `bash -n` (no-exec syntax check) so verification can never mutate
    /// the system. Returns false on a syntax error.
    /// - Parameter fix: The SuggestedFix to verify
    /// - Returns: True if the command parses as valid shell
    public static func verifyFix(_ fix: SuggestedFix) async -> Bool {
        do {
            _ = try await executeCommand("bash -n -c \(shellQuote(fix.command))")
            return true
        } catch {
            return false
        }
    }

    /// Single-quotes a string for safe embedding in a shell command.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    /// Executes a fix with user confirmation and returns execution record
    /// - Parameter fix: The SuggestedFix to execute
    /// - Returns: FixExecutionRecord with execution details
    public static func executeFixWithConfirmation(_ fix: SuggestedFix) async throws -> FixExecutionRecord {
        let startTime = Date()
        
        do {
            let output = try await executeCommand(fix.command)
            let record = FixExecutionRecord(
                fix: fix,
                output: output,
                success: true,
                timestamp: startTime
            )
            return record
        } catch {
            let record = FixExecutionRecord(
                fix: fix,
                output: error.localizedDescription,
                success: false,
                timestamp: startTime
            )
            return record
        }
    }
    
    // MARK: - Private Methods
    
    private static func executeCommandSync(_ command: String, timeout: TimeInterval = commandTimeout) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up a timer for command timeout
        var isTimedOut = false
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            isTimedOut = true
            process.terminate()
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            timer.invalidate()

            // Check if process was terminated due to timeout
            if isTimedOut {
                throw FixExecutionError.commandTimeout
            }

            // Capture output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            // Check exit status
            if process.terminationStatus != 0 {
                let errorMessage = !errorOutput.isEmpty ? errorOutput : output
                throw FixExecutionError.commandFailed(
                    exitCode: Int(process.terminationStatus),
                    output: errorMessage
                )
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as FixExecutionError {
            timer.invalidate()
            throw error
        } catch {
            timer.invalidate()
            throw FixExecutionError.executionError(error.localizedDescription)
        }
    }
}

// MARK: - Support Types

public struct FixExecutionRecord {
    public let fix: SuggestedFix
    public let output: String
    public let success: Bool
    public let timestamp: Date
    
    public init(
        fix: SuggestedFix,
        output: String,
        success: Bool,
        timestamp: Date = Date()
    ) {
        self.fix = fix
        self.output = output
        self.success = success
        self.timestamp = timestamp
    }
}

public enum FixExecutionError: LocalizedError {
    case commandFailed(exitCode: Int, output: String)
    case commandTimeout
    case executionError(String)
    
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let output):
            return "Command failed with exit code \(exitCode): \(output)"
        case .commandTimeout:
            return "Command execution timed out after 30 seconds"
        case .executionError(let message):
            return "Execution error: \(message)"
        }
    }
}
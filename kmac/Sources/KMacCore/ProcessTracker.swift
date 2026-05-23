import Foundation

public struct ProcessTracker: Sendable {
    public init() {}
    
    // MARK: - Public Methods
    
    /// Retrieves all currently running processes
    public func getRunningProcesses() async -> [ProcessMetrics] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._getRunningProcessesSync()
                continuation.resume(returning: result)
            }
        }
    }

    /// Retrieves information about a specific process by PID
    public func getProcessInfo(pid: Int) async -> ProcessMetrics? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._getProcessInfoSync(pid: pid)
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Terminates a process by PID
    public func killProcess(_ pid: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                do {
                    try self._killProcessSync(pid)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func _getRunningProcessesSync() -> [ProcessMetrics] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-aux"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return parseProcessOutput(output)
            }
        } catch {
            return []
        }
        
        return []
    }
    
    private func _getProcessInfoSync(pid: Int) -> ProcessMetrics? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-aux"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let processes = parseProcessOutput(output)
                return processes.first(where: { $0.pid == pid })
            }
        } catch {
            return nil
        }

        return nil
    }
    
    private func _killProcessSync(_ pid: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [String(pid)]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw ProcessTrackerError.killFailed(pid: pid, status: Int(process.terminationStatus))
            }
        } catch let error as ProcessTrackerError {
            throw error
        } catch {
            throw ProcessTrackerError.killFailed(pid: pid, status: -1)
        }
    }
    
    private func parseProcessOutput(_ output: String) -> [ProcessMetrics] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var processes: [ProcessMetrics] = []

        // Skip header line
        for line in lines.dropFirst() {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)

            guard components.count >= 11 else { continue }

            let pidString = String(components[1])
            let cpuString = String(components[2])
            let memString = String(components[3])
            let commandComponents = components.dropFirst(10)
            let command = commandComponents.joined(separator: " ")

            guard let pid = Int(pidString),
                  let cpu = Double(cpuString),
                  let memory = Double(memString) else {
                continue
            }

            let processMetrics = ProcessMetrics(
                name: command,
                pid: pid,
                cpuUsage: cpu,
                memoryUsage: memory
            )

            processes.append(processMetrics)
        }

        return processes
    }
}

// MARK: - Error Types

public enum ProcessTrackerError: Error {
    case killFailed(pid: Int, status: Int)
    case processNotFound(pid: Int)
}

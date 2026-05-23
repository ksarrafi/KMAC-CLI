import Foundation
import Darwin

public class SystemMonitor: @unchecked Sendable {
    public init() {}
    
    // MARK: - Public Methods
    
    /// Captures a snapshot of current system health metrics
    public func captureSnapshot() async -> HealthSnapshot {
        let cpuUsage = await getCPUUsage()
        let memoryUsage = await getMemoryUsage()
        let diskUsage = await getDiskUsage()
        let timestamp = Date()
        
        // Determine health status based on metrics
        let status = determineHealthStatus(
            cpu: cpuUsage,
            memory: memoryUsage,
            disk: diskUsage
        )
        
        return HealthSnapshot(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            timestamp: timestamp,
            status: status
        )
    }
    
    /// Retrieves information about the top running processes
    public func getTopProcesses(count: Int = 5) async -> [ProcessMetrics] {
        return await parseProcessList(limit: count)
    }
    
    /// Determines overall system health status
    public func getSystemHealth() async -> SystemHealthStatus {
        let snapshot = await captureSnapshot()
        return snapshot.status
    }
    
    // MARK: - Private Methods
    
    private func getCPUUsage() async -> Double {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._getCPUUsageSync()
                continuation.resume(returning: result)
            }
        }
    }
    
    private func _getCPUUsageSync() -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "1", "-n", "0"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return parseCPUFromTopOutput(output)
            }
        } catch {
            return 0.0
        }
        
        return 0.0
    }
    
    private func parseCPUFromTopOutput(_ output: String) -> Double {
        let lines = output.split(separator: "\n")
        for line in lines {
            if line.contains("CPU usage:") {
                let components = line.split(separator: "%")
                if let firstComponent = components.first {
                    let parts = firstComponent.split(separator: " ")
                    if let lastPart = parts.last,
                       let cpuValue = Double(lastPart) {
                        return cpuValue
                    }
                }
            }
        }
        return 0.0
    }
    
    private func getMemoryUsage() async -> Double {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._getMemoryUsageSync()
                continuation.resume(returning: result)
            }
        }
    }
    
    private func _getMemoryUsageSync() -> Double {
        let processInfo = Foundation.ProcessInfo.processInfo
        let physicalMemory = Double(processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        let usedMemory = Double(stats.active_count + stats.inactive_count + stats.wire_count) * Double(vm_page_size)
        let percentageUsed = (usedMemory / physicalMemory) * 100.0
        
        return min(percentageUsed, 100.0)
    }
    
    private func getDiskUsage() async -> Double {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._getDiskUsageSync()
                continuation.resume(returning: result)
            }
        }
    }
    
    private func _getDiskUsageSync() -> Double {
        let fileManager = FileManager.default
        guard let homeDirectory = fileManager.homeDirectoryForCurrentUser as NSURL? as URL? else {
            return 0.0
        }
        
        do {
            let resources = try homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            guard let availableCapacity = resources.volumeAvailableCapacity,
                  let totalCapacity = resources.volumeTotalCapacity else {
                return 0.0
            }
            
            let usedCapacity = totalCapacity - availableCapacity
            let percentageUsed = (Double(usedCapacity) / Double(totalCapacity)) * 100.0
            
            return min(percentageUsed, 100.0)
        } catch {
            return 0.0
        }
    }
    
    private func parseProcessList(limit: Int) async -> [ProcessMetrics] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                let result = self._parseProcessListSync(limit: limit)
                continuation.resume(returning: result)
            }
        }
    }

    private func _parseProcessListSync(limit: Int) -> [ProcessMetrics] {
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
                return parseProcessOutput(output, limit: limit)
            }
        } catch {
            return []
        }
        
        return []
    }
    
    private func parseProcessOutput(_ output: String, limit: Int) -> [ProcessMetrics] {
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

            if processes.count >= limit {
                break
            }
        }

        return processes.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(limit).map { $0 }
    }
    
    private func determineHealthStatus(cpu: Double, memory: Double, disk: Double) -> SystemHealthStatus {
        if cpu > 95 || memory > 95 || disk > 95 {
            return .critical
        } else if cpu > 80 || memory > 85 || disk > 90 {
            return .warning
        } else {
            return .healthy
        }
    }
}

import Foundation

// MARK: - System Health Models

public enum SystemHealthStatus: Equatable {
    case healthy
    case warning
    case critical
}

public struct HealthSnapshot {
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let diskUsage: Double
    public let timestamp: Date
    public let status: SystemHealthStatus
    
    public init(
        cpuUsage: Double,
        memoryUsage: Double,
        diskUsage: Double,
        timestamp: Date = Date(),
        status: SystemHealthStatus
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.timestamp = timestamp
        self.status = status
    }
}

// MARK: - Process Models

public struct ProcessMetrics {
    public let name: String
    public let pid: Int
    public let cpuUsage: Double
    public let memoryUsage: Double

    public init(
        name: String,
        pid: Int,
        cpuUsage: Double,
        memoryUsage: Double
    ) {
        self.name = name
        self.pid = pid
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
    }
}

// MARK: - Suggested Fix Models

public struct SuggestedFix: Codable {
    public let title: String
    public let description: String
    public let command: String
    public let severity: String
    
    public init(
        title: String,
        description: String,
        command: String,
        severity: String
    ) {
        self.title = title
        self.description = description
        self.command = command
        self.severity = severity
    }
}

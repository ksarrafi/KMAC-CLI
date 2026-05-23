import Foundation

public struct HealthAnalyzer {
    public init() {}
    
    // MARK: - Public Methods
    
    /// Analyzes a health snapshot and returns a list of identified issues
    public func analyzeHealth(_ snapshot: HealthSnapshot) -> [String] {
        var issues: [String] = []
        
        // Check CPU usage
        if snapshot.cpuUsage > 95 {
            issues.append("CRITICAL: CPU usage is at \(String(format: "%.1f", snapshot.cpuUsage))%")
        } else if snapshot.cpuUsage > 80 {
            issues.append("WARNING: CPU usage is high at \(String(format: "%.1f", snapshot.cpuUsage))%")
        }
        
        // Check memory usage
        if snapshot.memoryUsage > 95 {
            issues.append("CRITICAL: Memory usage is at \(String(format: "%.1f", snapshot.memoryUsage))%")
        } else if snapshot.memoryUsage > 85 {
            issues.append("WARNING: Memory usage is high at \(String(format: "%.1f", snapshot.memoryUsage))%")
        }
        
        // Check disk usage
        if snapshot.diskUsage > 95 {
            issues.append("CRITICAL: Disk usage is at \(String(format: "%.1f", snapshot.diskUsage))%")
        } else if snapshot.diskUsage > 90 {
            issues.append("WARNING: Disk usage is high at \(String(format: "%.1f", snapshot.diskUsage))%")
        }
        
        return issues
    }
    
    /// Determines the severity level of a health snapshot
    public func getSeverity(_ snapshot: HealthSnapshot) -> SystemHealthStatus {
        if snapshot.cpuUsage > 95 || snapshot.memoryUsage > 95 || snapshot.diskUsage > 95 {
            return .critical
        } else if snapshot.cpuUsage > 80 || snapshot.memoryUsage > 85 || snapshot.diskUsage > 90 {
            return .warning
        } else {
            return .healthy
        }
    }
}

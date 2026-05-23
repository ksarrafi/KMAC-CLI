import Foundation

public struct SystemStatus {
    public init() {}
    
    public func printStatus() {
        print("KMac System Status")
        print("==================")
        print("System: \(getSystemInfo())")
        print("Memory: \(getMemoryInfo())")
        print("Disk: \(getDiskInfo())")
    }
    
    private func getSystemInfo() -> String {
        let processInfo = ProcessInfo.processInfo
        return "\(processInfo.operatingSystemVersionString)"
    }
    
    private func getMemoryInfo() -> String {
        let memoryFootprint = Formatter.memoryFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory))
        return "Total: \(memoryFootprint)"
    }
    
    private func getDiskInfo() -> String {
        return "Available"
    }
}

// MARK: - Formatters

private struct Formatter {
    static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()
}

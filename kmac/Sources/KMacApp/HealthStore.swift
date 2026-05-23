import Foundation
import Combine
import KMacCore

/// Observable adapter around KMacCore's headless engine so SwiftUI can react
/// to live metrics. This is the single bridge between the GUI and the shared
/// backend — the app holds no metric logic of its own.
@MainActor
final class HealthStore: ObservableObject {
    @Published private(set) var snapshot: HealthSnapshot?
    @Published private(set) var issues: [String] = []

    private let monitor = SystemMonitor()
    private let analyzer = HealthAnalyzer()
    private var pollTask: Task<Void, Never>?

    /// Begins periodic sampling. Cheap; safe to call once at launch.
    func startPolling(interval: TimeInterval = 5.0) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Takes one snapshot now and publishes it.
    func refresh() async {
        let snap = await monitor.captureSnapshot()
        self.snapshot = snap
        self.issues = analyzer.analyzeHealth(snap)
    }

    /// System context string handed to Claude alongside a question.
    var claudeContext: String {
        guard let s = snapshot else { return "System metrics unavailable." }
        return """
        System Status:
        CPU: \(String(format: "%.1f", s.cpuUsage))%
        Memory: \(String(format: "%.1f", s.memoryUsage))%
        Disk: \(String(format: "%.1f", s.diskUsage))%
        Health: \(s.status.label)
        Timestamp: \(s.timestamp)
        """
    }
}

extension SystemHealthStatus {
    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

import XCTest
@testable import KMacCore

// Tests for HealthAnalyzer.getSeverity and analyzeHealth.
// Threshold reference (from HealthAnalyzer.swift):
//   CPU:    > 95 → critical,  > 80 → warning
//   Memory: > 95 → critical,  > 85 → warning
//   Disk:   > 95 → critical,  > 90 → warning
final class HealthAnalyzerTests: XCTestCase {

    private let analyzer = HealthAnalyzer()

    // MARK: - Helpers

    private func snapshot(cpu: Double = 0, mem: Double = 0, disk: Double = 0) -> HealthSnapshot {
        HealthSnapshot(cpuUsage: cpu, memoryUsage: mem, diskUsage: disk, status: .healthy)
    }

    // MARK: - getSeverity: healthy

    func testSeverity_allZero_isHealthy() {
        XCTAssertEqual(analyzer.getSeverity(snapshot()), .healthy)
    }

    func testSeverity_cpuAtExactly80_isHealthy() {
        // > 80 triggers warning, so exactly 80 should be healthy
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 80.0)), .healthy)
    }

    func testSeverity_memAtExactly85_isHealthy() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(mem: 85.0)), .healthy)
    }

    func testSeverity_diskAtExactly90_isHealthy() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(disk: 90.0)), .healthy)
    }

    // MARK: - getSeverity: warning

    func testSeverity_cpuJustAbove80_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 80.1)), .warning)
    }

    func testSeverity_cpuAt95_isWarning() {
        // 95 is not > 95, so it's warning not critical
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 95.0)), .warning)
    }

    func testSeverity_memJustAbove85_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(mem: 85.1)), .warning)
    }

    func testSeverity_memAt95_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(mem: 95.0)), .warning)
    }

    func testSeverity_diskJustAbove90_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(disk: 90.1)), .warning)
    }

    func testSeverity_diskAt95_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(disk: 95.0)), .warning)
    }

    // MARK: - getSeverity: critical

    func testSeverity_cpuJustAbove95_isCritical() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 95.1)), .critical)
    }

    func testSeverity_cpuAt100_isCritical() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 100.0)), .critical)
    }

    func testSeverity_memJustAbove95_isCritical() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(mem: 95.1)), .critical)
    }

    func testSeverity_diskJustAbove95_isCritical() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(disk: 95.1)), .critical)
    }

    // MARK: - getSeverity: highest dimension wins

    func testSeverity_criticalCpuOverridesHealthyRest() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 96, mem: 50, disk: 50)), .critical)
    }

    func testSeverity_criticalMemOverridesWarningCpu() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 81, mem: 96, disk: 50)), .critical)
    }

    func testSeverity_warningCpuHealthyOthers_isWarning() {
        XCTAssertEqual(analyzer.getSeverity(snapshot(cpu: 85, mem: 50, disk: 50)), .warning)
    }

    // MARK: - analyzeHealth: no issues

    func testAnalyzeHealth_allHealthy_returnsEmpty() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 50, mem: 50, disk: 50))
        XCTAssertTrue(issues.isEmpty, "Expected no issues but got: \(issues)")
    }

    func testAnalyzeHealth_atExactThresholds_returnsEmpty() {
        // Exactly at boundary values (not exceeding) → no issues
        let issues = analyzer.analyzeHealth(snapshot(cpu: 80.0, mem: 85.0, disk: 90.0))
        XCTAssertTrue(issues.isEmpty, "Expected no issues but got: \(issues)")
    }

    // MARK: - analyzeHealth: CPU issues

    func testAnalyzeHealth_cpuWarning_includesCpuWarning() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 81.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].hasPrefix("WARNING: CPU"), "Expected CPU warning, got: \(issues[0])")
    }

    func testAnalyzeHealth_cpuCritical_includesCpuCritical() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 96.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].hasPrefix("CRITICAL: CPU"), "Expected CPU critical, got: \(issues[0])")
    }

    func testAnalyzeHealth_cpuWarning_doesNotContainCriticalPrefix() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 90.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertFalse(issues[0].hasPrefix("CRITICAL"))
        XCTAssertTrue(issues[0].hasPrefix("WARNING"))
    }

    // MARK: - analyzeHealth: memory issues

    func testAnalyzeHealth_memWarning_includesMemWarning() {
        let issues = analyzer.analyzeHealth(snapshot(mem: 86.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Memory") && issues[0].hasPrefix("WARNING"),
                      "Got: \(issues[0])")
    }

    func testAnalyzeHealth_memCritical_includesMemCritical() {
        let issues = analyzer.analyzeHealth(snapshot(mem: 96.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Memory") && issues[0].hasPrefix("CRITICAL"),
                      "Got: \(issues[0])")
    }

    // MARK: - analyzeHealth: disk issues

    func testAnalyzeHealth_diskWarning_includesDiskWarning() {
        let issues = analyzer.analyzeHealth(snapshot(disk: 91.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Disk") && issues[0].hasPrefix("WARNING"),
                      "Got: \(issues[0])")
    }

    func testAnalyzeHealth_diskCritical_includesDiskCritical() {
        let issues = analyzer.analyzeHealth(snapshot(disk: 96.0))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Disk") && issues[0].hasPrefix("CRITICAL"),
                      "Got: \(issues[0])")
    }

    // MARK: - analyzeHealth: multiple issues

    func testAnalyzeHealth_allCritical_returnsThreeIssues() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 96, mem: 96, disk: 96))
        XCTAssertEqual(issues.count, 3, "Expected 3 critical issues, got: \(issues)")
    }

    func testAnalyzeHealth_cpuAndMemWarning_returnsTwoIssues() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 85, mem: 88, disk: 50))
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues[0].contains("CPU"))
        XCTAssertTrue(issues[1].contains("Memory"))
    }

    func testAnalyzeHealth_issueContainsFormattedPercentage() {
        let issues = analyzer.analyzeHealth(snapshot(cpu: 88.5))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("88.5"), "Issue should include formatted CPU value, got: \(issues[0])")
    }
}

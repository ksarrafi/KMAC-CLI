import Foundation
import KMacCore

@main
struct KMacCLI {
    static func main() async {
        let arguments = CommandLine.arguments

        if arguments.count < 2 {
            printUsage()
            return
        }

        let command = arguments[1]

        switch command {
        case "status":
            await handleStatus()
        case "ask":
            let query = arguments.count > 2 ? arguments[2...].joined(separator: " ") : ""
            await handleAsk(query: query)
        case "fix":
            await handleFix()
        case "execute-fix":
            let index = arguments.count > 2 ? Int(arguments[2]) : nil
            await handleExecuteFix(index: index)
        case "monitor":
            await handleMonitor()
        case "spotlight":
            handleSpotlight()
        case "help":
            printUsage()
        case "version":
            print("kmac version 1.0.0")
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    private static func handleStatus() async {
        let monitor = SystemMonitor()
        let snapshot = await monitor.captureSnapshot()
        let analyzer = HealthAnalyzer()
        let health = analyzer.getSeverity(snapshot)

        print("KMac System Status")
        print("==================")
        print("CPU Usage:    \(String(format: "%.1f", snapshot.cpuUsage))%")
        print("Memory Usage: \(String(format: "%.1f", snapshot.memoryUsage))%")
        print("Disk Usage:   \(String(format: "%.1f", snapshot.diskUsage))%")
        print("Health:       \(health)")
        print("Timestamp:    \(snapshot.timestamp)")

        let issues = analyzer.analyzeHealth(snapshot)
        if !issues.isEmpty {
            print("\nIssues detected:")
            for issue in issues {
                print("  • \(issue)")
            }
        } else {
            print("\n✓ System is healthy")
        }
    }

    private static func handleAsk(query: String) async {
        guard !query.isEmpty else {
            print("Error: Please provide a query")
            print("Usage: kmac ask \"your question\"")
            return
        }

        let monitor = SystemMonitor()
        let snapshot = await monitor.captureSnapshot()

        let context = """
        System Status:
        CPU: \(String(format: "%.1f", snapshot.cpuUsage))%
        Memory: \(String(format: "%.1f", snapshot.memoryUsage))%
        Disk: \(String(format: "%.1f", snapshot.diskUsage))%
        Timestamp: \(snapshot.timestamp)
        """

        print("Analyzing system and asking Claude...\n")

        do {
            let api = try ClaudeAPI()
            var fullResponse = ""
            for try await chunk in api.askClaude(query: query, systemContext: context) {
                print(chunk, terminator: "")
                fullResponse += chunk
                fflush(stdout)
            }
            print("\n")

            // Check for suggested fixes
            let fixes = api.parseSuggestedFixes(response: fullResponse)
            if !fixes.isEmpty {
                print("Suggested fixes available. Use 'kmac fix' to see details.")
            }
        } catch {
            print("Error: \(error)")
        }
    }

    private static func handleFix() async {
        let monitor = SystemMonitor()
        let snapshot = await monitor.captureSnapshot()
        let analyzer = HealthAnalyzer()

        let issues = analyzer.analyzeHealth(snapshot)

        if issues.isEmpty {
            print("✓ System is healthy. No immediate fixes needed.")
            return
        }

        print("Issues detected:")
        for issue in issues {
            print("  • \(issue)")
        }
        print("")

        let issueDescription = issues.joined(separator: ", ")
        let query = "System has these issues: \(issueDescription). Provide specific terminal commands to fix them."

        print("Generating fixes from Claude...\n")

        do {
            let api = try ClaudeAPI()
            var fullResponse = ""
            for try await chunk in api.askClaude(query: query, systemContext: "System health analysis") {
                print(chunk, terminator: "")
                fullResponse += chunk
                fflush(stdout)
            }
            print("\n")

            let fixes = api.parseSuggestedFixes(response: fullResponse)
            if !fixes.isEmpty {
                do {
                    try FixStore.save(fixes)
                } catch {
                    print("Warning: could not save fixes: \(error.localizedDescription)")
                }
                print("\nFound \(fixes.count) suggested fix(es):")
                for (i, fix) in fixes.enumerated() {
                    print("  [\(i + 1)] \(fix.title)")
                }
                print("\nRun one with: kmac execute-fix <number>")
            }
        } catch {
            print("Error: \(error)")
        }
    }

    private static func handleExecuteFix(index: Int?) async {
        let fixes = FixStore.load()

        guard !fixes.isEmpty else {
            print("No saved fixes. Run 'kmac fix' first.")
            return
        }

        guard let index = index, index >= 1, index <= fixes.count else {
            print("Usage: kmac execute-fix <number>")
            print("Available fixes:")
            for (i, fix) in fixes.enumerated() {
                print("  [\(i + 1)] \(fix.title)")
            }
            return
        }

        let fix = fixes[index - 1]

        print("Fix [\(index)]: \(fix.title)")
        print("Severity: \(fix.severity)")
        print("Description: \(fix.description)")
        print("\nCommand to run:")
        print("  \(fix.command)")
        print("\nThis will execute the above shell command. Continue? [y/N] ", terminator: "")

        guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              answer == "y" || answer == "yes" else {
            print("Aborted.")
            return
        }

        print("\nExecuting...\n")
        let record = try? await FixExecutor.executeFixWithConfirmation(fix)

        guard let record = record else {
            print("Execution failed to start.")
            return
        }

        if record.success {
            print("✓ Success")
            if !record.output.isEmpty {
                print(record.output)
            }
        } else {
            print("✗ Failed")
            print(record.output)
        }
    }

    private static func handleMonitor() async {
        print("Starting system monitoring (Ctrl+C to stop)...\n")

        let monitor = SystemMonitor()
        let analyzer = HealthAnalyzer()

        for i in 0..<5 {
            let snapshot = await monitor.captureSnapshot()
            let health = analyzer.getSeverity(snapshot)

            let timeFormatter = ISO8601DateFormatter()
            let timeString = timeFormatter.string(from: snapshot.timestamp)

            print("[\(i + 1)/5] [\(timeString)] CPU: \(String(format: "%.1f", snapshot.cpuUsage))% | Memory: \(String(format: "%.1f", snapshot.memoryUsage))% | Disk: \(String(format: "%.1f", snapshot.diskUsage))% | Status: \(health)")

            if i < 4 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\nMonitoring complete.")
    }

    private static func handleSpotlight() {
        guard let appPath = locateSpotlightApp() else {
            print("KMac.app not found.")
            print("Build it first:  ./build-app.sh")
            print("Then optionally: cp -r KMac.app /Applications/")
            return
        }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [appPath]
        do {
            try open.run()
            open.waitUntilExit()
            print("Launched KMac.app — press ⌘K to open the Spotlight panel.")
            print("(First run: grant Accessibility permission in System Settings")
            print(" > Privacy & Security > Accessibility for the global ⌘K hotkey.)")
        } catch {
            print("Failed to launch KMac.app: \(error.localizedDescription)")
        }
    }

    /// Searches the usual locations for the built menu-bar app bundle.
    private static func locateSpotlightApp() -> String? {
        let fm = FileManager.default
        var candidates = ["/Applications/KMac.app"]

        // Alongside the running CLI binary and its parent (repo checkout).
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("KMac.app").path)
        candidates.append(exeDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KMac.app").path)
        candidates.append(fm.currentDirectoryPath + "/KMac.app")

        return candidates.first { fm.fileExists(atPath: $0) }
    }

    private static func printUsage() {
        print("""
        kmac - Mac Health & AI Fixer CLI

        Usage: kmac <command> [options]

        Commands:
          status              Show system status
          ask <query>         Ask Claude about your system
          fix                 Detect issues and get suggested fixes
          execute-fix <n>     Run suggested fix number <n> from last 'fix'
          monitor             Monitor system health (5 samples)
          spotlight           Launch the Spotlight visual interface
          help                Show this help message
          version             Show version information

        Examples:
          kmac status
          kmac ask "Why is my CPU high?"
          kmac fix
          kmac execute-fix 1
          kmac monitor
          kmac spotlight
        """)
    }
}

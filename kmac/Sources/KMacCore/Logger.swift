import Foundation

public class Logger {
    
    // MARK: - Shared Instance
    
    public static let shared = Logger()
    
    // MARK: - Properties
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Logs a message at the specified log level
    public func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)"
        
        // Output to stderr
        fputs(logMessage + "\n", stderr)
    }
    
    /// Logs an error message
    public func error(_ message: String) {
        log(message, level: .error)
    }
    
    /// Logs a debug message
    public func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    /// Logs an info message
    public func info(_ message: String) {
        log(message, level: .info)
    }
    
    /// Logs a warning message
    public func warning(_ message: String) {
        log(message, level: .warning)
    }
}

// MARK: - Log Level Enum

public enum LogLevel: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
}
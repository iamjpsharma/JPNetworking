//
//  Logger.swift
//  JPNetworking
//
//  Comprehensive logging system for JPNetworking framework.
//  Provides structured logging, multiple output destinations,
//  and configurable log levels for debugging and monitoring.
//

import Foundation
import os.log

// MARK: - Log Level

/// Log levels for JPNetworking logging system
public enum LogLevel: Int, CaseIterable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
    
    /// String representation of log level
    public var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
    
    /// Emoji representation for console output
    public var emoji: String {
        switch self {
        case .verbose: return "💬"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Log Destination Protocol

/// Protocol for log output destinations
public protocol LogDestination: Sendable {
    /// Write log entry to destination
    /// - Parameter entry: Log entry to write
    func write(_ entry: LogEntry) async
    
    /// Destination identifier
    var identifier: String { get }
    
    /// Minimum log level for this destination
    var minimumLogLevel: LogLevel { get }
}

// MARK: - Log Entry

/// Represents a single log entry
public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let category: String
    public let file: String
    public let function: String
    public let line: Int
    public let metadata: [String: String]
    
    /// Formatted log message
    public var formattedMessage: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        let timestamp = dateFormatter.string(from: self.timestamp)
        let fileName = (file as NSString).lastPathComponent
        
        return "\(timestamp) [\(level.description)] [\(category)] \(message) (\(fileName):\(line) \(function))"
    }
    
    /// Console-friendly formatted message with emoji
    public var consoleMessage: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        let timestamp = dateFormatter.string(from: self.timestamp)
        let fileName = (file as NSString).lastPathComponent
        
        return "\(level.emoji) \(timestamp) [\(category)] \(message) (\(fileName):\(line))"
    }
}

// MARK: - Console Log Destination

/// Console log destination using print()
public struct ConsoleLogDestination: LogDestination {
    public let identifier = "JPNetworking.ConsoleLogger"
    public let minimumLogLevel: LogLevel
    private let useEmoji: Bool
    
    /// Initialize console log destination
    /// - Parameters:
    ///   - minimumLogLevel: Minimum log level to output
    ///   - useEmoji: Whether to use emoji in output
    public init(minimumLogLevel: LogLevel = .info, useEmoji: Bool = true) {
        self.minimumLogLevel = minimumLogLevel
        self.useEmoji = useEmoji
    }
    
    public func write(_ entry: LogEntry) async {
        guard entry.level.rawValue >= minimumLogLevel.rawValue else { return }
        
        let message = useEmoji ? entry.consoleMessage : entry.formattedMessage
        print(message)
        
        // Print metadata if present
        if !entry.metadata.isEmpty {
            for (key, value) in entry.metadata {
                print("  \(key): \(value)")
            }
        }
    }
}

// MARK: - File Log Destination

/// File log destination for persistent logging
public struct FileLogDestination: LogDestination {
    public let identifier = "JPNetworking.FileLogger"
    public let minimumLogLevel: LogLevel
    private let fileURL: URL
    private let maxFileSize: Int
    private let maxFiles: Int
    
    /// Initialize file log destination
    /// - Parameters:
    ///   - fileURL: URL for log file
    ///   - minimumLogLevel: Minimum log level to write
    ///   - maxFileSize: Maximum file size before rotation (bytes)
    ///   - maxFiles: Maximum number of log files to keep
    public init(
        fileURL: URL,
        minimumLogLevel: LogLevel = .debug,
        maxFileSize: Int = 10 * 1024 * 1024, // 10MB
        maxFiles: Int = 5
    ) {
        self.fileURL = fileURL
        self.minimumLogLevel = minimumLogLevel
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
    }
    
    public func write(_ entry: LogEntry) async {
        guard entry.level.rawValue >= minimumLogLevel.rawValue else { return }
        
        let logLine = entry.formattedMessage + "\n"
        
        // Create directory if needed
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Write to file
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                // Create new file
                try? data.write(to: fileURL)
            }
        }
        
        // Check for file rotation
        await rotateLogsIfNeeded()
    }
    
    private func rotateLogsIfNeeded() async {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize > maxFileSize else {
            return
        }
        
        // Rotate log files
        let fileManager = FileManager.default
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        let directory = fileURL.deletingLastPathComponent()
        
        // Move existing rotated files
        for i in (1..<maxFiles).reversed() {
            let oldFile = directory.appendingPathComponent("\(fileName).\(i).\(fileExtension)")
            let newFile = directory.appendingPathComponent("\(fileName).\(i + 1).\(fileExtension)")
            
            if fileManager.fileExists(atPath: oldFile.path) {
                try? fileManager.moveItem(at: oldFile, to: newFile)
            }
        }
        
        // Move current file to .1
        let rotatedFile = directory.appendingPathComponent("\(fileName).1.\(fileExtension)")
        try? fileManager.moveItem(at: fileURL, to: rotatedFile)
    }
}

// MARK: - OS Log Destination

/// OS Log destination using Apple's unified logging system
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
public struct OSLogDestination: LogDestination {
    public let identifier = "JPNetworking.OSLogger"
    public let minimumLogLevel: LogLevel
    private let logger: os.Logger
    
    /// Initialize OS Log destination
    /// - Parameters:
    ///   - subsystem: Subsystem identifier
    ///   - category: Category identifier
    ///   - minimumLogLevel: Minimum log level to log
    public init(
        subsystem: String = "com.swiftnet.framework",
        category: String = "networking",
        minimumLogLevel: LogLevel = .info
    ) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
        self.minimumLogLevel = minimumLogLevel
    }
    
    public func write(_ entry: LogEntry) async {
        guard entry.level.rawValue >= minimumLogLevel.rawValue else { return }
        
        let message = "\(entry.message) (\((entry.file as NSString).lastPathComponent):\(entry.line))"
        
        switch entry.level {
        case .verbose, .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.notice("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .critical:
            logger.critical("\(message, privacy: .public)")
        }
    }
}

// MARK: - JPNetworking Logger

/// Main logger for JPNetworking framework
@globalActor
public actor JPNetworkingLogger {
    
    public static let shared = JPNetworkingLogger()
    
    // MARK: - Properties
    
    private var destinations: [LogDestination] = []
    private var isEnabled = true
    private var globalMetadata: [String: String] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Add default console destination
        destinations.append(ConsoleLogDestination())
    }
    
    // MARK: - Configuration
    
    /// Enable or disable logging
    /// - Parameter enabled: Whether logging is enabled
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    /// Add a log destination
    /// - Parameter destination: Log destination to add
    public func addDestination(_ destination: LogDestination) {
        destinations.append(destination)
    }
    
    /// Remove a log destination by identifier
    /// - Parameter identifier: Destination identifier
    public func removeDestination(withIdentifier identifier: String) {
        destinations.removeAll { $0.identifier == identifier }
    }
    
    /// Remove all log destinations
    public func removeAllDestinations() {
        destinations.removeAll()
    }
    
    /// Set global metadata that will be included in all log entries
    /// - Parameter metadata: Global metadata dictionary
    public func setGlobalMetadata(_ metadata: [String: String]) {
        globalMetadata = metadata
    }
    
    /// Add global metadata
    /// - Parameters:
    ///   - key: Metadata key
    ///   - value: Metadata value
    public func addGlobalMetadata(key: String, value: String) {
        globalMetadata[key] = value
    }
    
    // MARK: - Logging Methods
    
    /// Log a message
    /// - Parameters:
    ///   - level: Log level
    ///   - message: Log message
    ///   - category: Log category
    ///   - metadata: Additional metadata
    ///   - file: Source file (automatically filled)
    ///   - function: Source function (automatically filled)
    ///   - line: Source line (automatically filled)
    public func log(
        level: LogLevel,
        message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }
        
        var combinedMetadata = globalMetadata
        for (key, value) in metadata {
            combinedMetadata[key] = value
        }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            category: category,
            file: file,
            function: function,
            line: line,
            metadata: combinedMetadata
        )
        
        Task {
            for destination in destinations {
                await destination.write(entry)
            }
        }
    }
    
    /// Log verbose message
    public func verbose(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .verbose, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log debug message
    public func debug(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log info message
    public func info(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log warning message
    public func warning(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log error message
    public func error(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log critical message
    public func critical(
        _ message: String,
        category: String = "JPNetworking",
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Global Functions

/// Global logging functions for easy access
public func JPNetworkingLog(
    level: LogLevel,
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await JPNetworkingLogger.shared.log(
            level: level,
            message: message,
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log verbose message
public func JPNetworkingVerbose(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .verbose, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/// Log debug message
public func JPNetworkingDebug(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .debug, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/// Log info message
public func JPNetworkingInfo(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .info, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/// Log warning message
public func JPNetworkingWarning(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .warning, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/// Log error message
public func JPNetworkingError(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .error, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/// Log critical message
public func JPNetworkingCritical(
    _ message: String,
    category: String = "JPNetworking",
    metadata: [String: String] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    JPNetworkingLog(level: .critical, message, category: category, metadata: metadata, file: file, function: function, line: line)
}

/*
 🛠️ LOGGING SYSTEM ARCHITECTURE EXPLANATION:
 
 1. STRUCTURED LOGGING:
    - LogLevel enum with priority-based filtering
    - LogEntry struct with comprehensive metadata
    - Category-based organization for different components
    - Automatic source location capture (file, function, line)
 
 2. MULTIPLE DESTINATIONS:
    - Console: For development and debugging
    - File: For persistent logging with rotation
    - OS Log: Integration with Apple's unified logging
    - Extensible protocol for custom destinations
 
 3. PRODUCTION FEATURES:
    - Configurable log levels per destination
    - Automatic log file rotation
    - Global metadata support
    - Thread-safe actor-based implementation
    - Performance-optimized async logging
 
 4. DEVELOPER EXPERIENCE:
    - Emoji support for visual distinction
    - Convenient global functions
    - Automatic source location
    - Structured metadata support
    - Easy configuration and customization
 
 5. INTEGRATION:
    - Used by interceptors for request/response logging
    - Cache and retry managers for debugging
    - Error tracking and monitoring
    - Performance metrics and analytics
 */

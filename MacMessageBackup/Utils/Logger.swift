import Foundation
import os

/// Simple logger for the application
class Logger {
    static let shared = Logger()
    
    private let logger: os.Logger
    private let logFileURL: URL
    
    private init() {
        logger = os.Logger(subsystem: "com.macmessagebackup", category: "general")
        
        // Log file in user's logs directory
        logFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MacMessageBackup/backup.log")
    }
    
    func info(_ message: String) {
        logger.info("\(message)")
        writeToFile("INFO", message)
    }
    
    func warning(_ message: String) {
        logger.warning("\(message)")
        writeToFile("WARN", message)
    }
    
    func error(_ message: String) {
        logger.error("\(message)")
        writeToFile("ERROR", message)
    }
    
    func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message)")
        writeToFile("DEBUG", message)
        #endif
    }
    
    private func writeToFile(_ level: String, _ message: String) {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level)] \(message)\n"
        
        do {
            let directory = logFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                handle.seekToEndOfFile()
                if let data = logLine.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try logLine.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silently ignore log write errors
        }
    }
    
    /// Get recent log entries
    func getRecentLogs(lines: Int = 100) -> String {
        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return "No logs available"
        }
        
        let allLines = content.components(separatedBy: .newlines)
        let recentLines = allLines.suffix(lines)
        return recentLines.joined(separator: "\n")
    }
    
    /// Clear log file
    func clearLogs() {
        try? FileManager.default.removeItem(at: logFileURL)
    }
}

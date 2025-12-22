import Foundation
import AppKit

/// Helper for checking and requesting system permissions
class PermissionHelper: ObservableObject {
    
    static let shared = PermissionHelper()
    
    @Published var hasFullDiskAccess: Bool = false
    
    private init() {
        // Defer check to avoid blocking init
    }
    
    /// Check if app has Full Disk Access permission (Synchronous - do not call on main thread)
    private func checkFullDiskAccessSync() -> Bool {
        // Try to access a protected file to test permission
        // The Messages database is a good test - requires Full Disk Access
        let testPaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Messages/chat.db").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CallHistoryDB/CallHistory.storedata").path
        ]
        
        for path in testPaths {
            if FileManager.default.fileExists(atPath: path) {
                // File exists, try to open it
                if let handle = FileHandle(forReadingAtPath: path) {
                    handle.closeFile()
                    return true
                }
            }
        }
        
        // Alternative: try to read the directory
        let messagesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages")
        
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: messagesDir.path)
            return true
        } catch {
            return false
        }
    }
    
    /// Trigger async permission check
    func checkFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let hasAccess = self.checkFullDiskAccessSync()
            
            DispatchQueue.main.async {
                self.hasFullDiskAccess = hasAccess
            }
        }
    }
    
    /// Open System Preferences to Full Disk Access pane
    func openFullDiskAccessSettings() {
        // macOS 13+ uses new URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Get the app's bundle URL for adding to Full Disk Access
    func getAppBundleURL() -> URL? {
        return Bundle.main.bundleURL
    }
    
    /// Refresh permission status (Async)
    func refreshPermissionStatus() {
        checkFullDiskAccess()
    }
}

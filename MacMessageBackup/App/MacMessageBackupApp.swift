import SwiftUI
import AppKit

/// Main application entry point
@main
struct MacMessageBackupApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Use @AppStorage to avoid triggering App.body rebuild when AppState changes
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    
    var body: some Scene {

        Window("Mac Message Backup", id: "main") {
            ContentView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // App is about to terminate
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Add custom commands
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "Quit Mac Message Backup")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        
        // Menu bar extra for quick access (always shown if enabled)
        // Use @AppStorage binding instead of @Published to prevent infinite refresh loop
        MenuBarExtra("Mac Message Backup", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        // Explicit Settings window for programmatic access
        Window(String(localized: "Settings"), id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 500, minHeight: 600) // Ensure reasonable size
        }
        .windowResizability(.contentSize)
    }
}

import ServiceManagement

/// App delegate for single instance check and window management
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Check if another instance is already running
        let runningApps = NSWorkspace.shared.runningApplications
        let myBundleId = Bundle.main.bundleIdentifier ?? "com.example.MacMessageBackup"
        
        let otherInstances = runningApps.filter {
            $0.bundleIdentifier == myBundleId && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        if !otherInstances.isEmpty {
            // Another instance is running - post notification to show window and quit
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name("com.MacMessageBackup.showWindow"),
                object: nil
            )
            
            // Quit this instance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        
        // Listen for show window notifications from other instances
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showMainWindowFromNotification),
            name: NSNotification.Name("com.MacMessageBackup.showWindow"),
            object: nil
        )
    }
    
    @objc func showMainWindowFromNotification() {
        DispatchQueue.main.async {
            self.showMainWindow()
        }
    }
    
    func showMainWindow() {
        // First, temporarily show in Dock if completely hidden (so window can be created)
        let config = BackupConfig.load()
        let wasCompletelyHidden = config.hideDockIcon && !config.showMenuBarIcon
        
        if wasCompletelyHidden {
            // Temporarily become regular app to allow window creation
            NSApp.setActivationPolicy(.regular)
        }
        
        // Activate app and show window
        NSApp.activate(ignoringOtherApps: true)
        
        // Try to find the main window (not menu bar extra)
        if let window = NSApp.windows.first(where: { window in
            window.styleMask.contains(.titled) && window.canBecomeKey
        }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()  // Force window to front
        } else if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        
        // If was completely hidden, go back to hidden after a short delay
        // This keeps Dock visible while window is open
        if wasCompletelyHidden {
            // Keep Dock visible while window is open - will hide when window closes
        }
    }
    
    // Handle Dock icon click when no windows are open
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    // Handle window close - hide instead of quit when Dock is hidden
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        // Return false to keep app running in menu bar even if window is closed
        return false
    }
    
    /// Update Dock visibility based on config
    func updateDockVisibility(hidden: Bool) {
        if hidden {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            // If switching to regular, make sure window is visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // MARK: - Login Item Management (macOS 13+)
    
    /// Set whether app should launch at login
    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
            }
        }
    }
    
    /// Check if app is set to launch at login
    static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}

/// Global application state
class AppState: ObservableObject {
    @Published var config: BackupConfig
    @Published var isBackingUp = false
    @Published var backupProgress = ""
    @Published var backupProgressValue: Double = 0 // 0.0 to 1.0
    @Published var lastBackupResult: BackupResult?
    @Published var statusMessage = "Ready"
    
    // Time throttling for UI updates (to prevent excessive view rebuilds)
    private var lastProgressUpdate: Date = .distantPast
    
    // Services - lazy initialization to reduce memory
    private var _messageService: MessageDatabaseService?
    var messageService: MessageDatabaseService {
        if _messageService == nil {
            _messageService = MessageDatabaseService()
        }
        return _messageService!
    }
    
    private var _callService: CallHistoryService?
    var callService: CallHistoryService {
        if _callService == nil {
            _callService = CallHistoryService()
        }
        return _callService!
    }
    
    var imapService: IMAPService?
    var calendarService: GoogleCalendarService?
    var scheduler: BackupScheduler?
    
    // Connection status - consolidated into single struct to reduce @Published count
    struct ConnectionStatus {
        var messagesDb = false
        var callHistoryDb = false
        var gmail = false
        var calendar = false
    }
    @Published var connectionStatus = ConnectionStatus()
    
    // Convenience accessors for backward compatibility
    var messagesDbConnected: Bool {
        get { connectionStatus.messagesDb }
        set { connectionStatus.messagesDb = newValue }
    }
    var callHistoryDbConnected: Bool {
        get { connectionStatus.callHistoryDb }
        set { connectionStatus.callHistoryDb = newValue }
    }
    var gmailConnected: Bool {
        get { connectionStatus.gmail }
        set { connectionStatus.gmail = newValue }
    }
    var calendarConnected: Bool {
        get { connectionStatus.calendar }
        set { connectionStatus.calendar = newValue }
    }
    
    // Statistics - consolidated into single struct
    struct BackupStatistics {
        var totalMessages = 0
        var totalCallRecords = 0
        var backedUpMessages = 0
        var backedUpCallRecords = 0
        var remainingMessages = 0
        var remainingCallRecords = 0
    }
    @Published var stats = BackupStatistics()
    
    // Convenience accessors for backward compatibility
    var totalMessages: Int {
        get { stats.totalMessages }
        set { stats.totalMessages = newValue }
    }
    var totalCallRecords: Int {
        get { stats.totalCallRecords }
        set { stats.totalCallRecords = newValue }
    }
    var backedUpMessages: Int {
        get { stats.backedUpMessages }
        set { stats.backedUpMessages = newValue }
    }
    var backedUpCallRecords: Int {
        get { stats.backedUpCallRecords }
        set { stats.backedUpCallRecords = newValue }
    }
    var remainingMessages: Int {
        get { stats.remainingMessages }
        set { stats.remainingMessages = newValue }
    }
    var remainingCallRecords: Int {
        get { stats.remainingCallRecords }
        set { stats.remainingCallRecords = newValue }
    }
    
    // App visibility - use @AppStorage instead of @Published to reduce overhead
    @Published var showMenuBarExtra: Bool = true
    var mainWindowVisible: Bool = true  // Non-published, rarely used
    
    // Log entries for display - limit to 30 to reduce memory
    @Published var logEntries: [LogEntry] = []
    
    /// Represents a log entry
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType
        
        enum LogType {
            case info, success, error, warning
            
            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .success: return "checkmark.circle"
                case .error: return "xmark.circle"
                case .warning: return "exclamationmark.triangle"
                }
            }
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .success: return .green  
                case .error: return .red
                case .warning: return .orange
                }
            }
        }
    }
    
    /// Add a log entry
    func addLog(_ message: String, type: LogEntry.LogType = .info) {
        DispatchQueue.main.async {
            self.logEntries.append(LogEntry(timestamp: Date(), message: message, type: type))
            // Keep only last 30 entries to reduce memory
            if self.logEntries.count > 30 {
                self.logEntries.removeFirst()
            }
        }
    }
    
    /// Clear all logs
    func clearLogs() {
        logEntries.removeAll()
    }
    
    // Temporary variables to track stats at backup start (for real-time update)
    private var backupStartBackedUpMessages = 0
    private var backupStartBackedUpCalls = 0
    
    // Alert state
    @Published var activeAlert: AlertItem?
    
    // Global UI State
    @Published var showSettings = false
    
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let type: AlertType
        
        enum AlertType {
            case info, success, error
        }
    }
    
    // ... (existing code)
    
    init() {
        self.config = BackupConfig.load()
        // Services are now lazily initialized when first accessed
        
        // Initial state is disconnected - connection happens in initializeServices()
        connectionStatus = ConnectionStatus()
        
        // Sync app visibility state from config
        // Use underscore prefix to set underlying storage directly, avoiding @Published notification during init
        _showMenuBarExtra = Published(initialValue: config.showMenuBarIcon)
        
        // Apply Dock visibility setting on launch
        if config.hideDockIcon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppDelegate.shared?.updateDockVisibility(hidden: true)
            }
        }
        
        // Initialize services
        if !config.email.isEmpty {
            imapService = IMAPService(config: config)
        }
        
        scheduler = BackupScheduler(config: config)
        scheduler?.onProgress = { [weak self] progress, message in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.backupProgress = message
                self.backupProgressValue = progress
                
                // Log messages that don't contain progress counters
                if !message.contains("/") {
                    self.addLog(message, type: message.contains("failed") || message.contains("error") ? .error : .info)
                }
            }
        }
        
        // Real-time incremental update - use saved values from backup start
        scheduler?.onIncrementalUpdate = { [weak self] messagesCount, callsCount in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if messagesCount > 0 {
                    self.backedUpMessages = self.backupStartBackedUpMessages + messagesCount
                    self.remainingMessages = self.totalMessages - self.backedUpMessages
                }
                if callsCount > 0 {
                    self.backedUpCallRecords = self.backupStartBackedUpCalls + callsCount
                    self.remainingCallRecords = self.totalCallRecords - self.backedUpCallRecords
                }
            }
        }
        
        scheduler?.onComplete = { [weak self] result, isAutoBackup in
            DispatchQueue.main.async {
                self?.isBackingUp = false
                switch result {
                case .success(let backupResult):
                    // Reload config to sync lastRowId updated by scheduler
                    self?.config = BackupConfig.load()
                    
                    self?.lastBackupResult = backupResult
                    self?.statusMessage = backupResult.summary
                    
                    // Refresh stats to update backed up counts
                    self?.refreshStats()
                    
                    // Log the result
                    if isAutoBackup {
                        self?.addLog(String(localized: "Auto backup completed: ") + backupResult.summary, type: .success)
                    } else {
                        // Show success alert only for manual backup
                        self?.activeAlert = AlertItem(
                            title: String(localized: "Backup Complete"),
                            message: backupResult.summary,
                            type: .success
                        )
                    }
                case .failure(let error):
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                    
                    if isAutoBackup {
                        self?.addLog(String(localized: "Auto backup failed: ") + error.localizedDescription, type: .error)
                    } else {
                        // Show error alert only for manual backup
                        self?.activeAlert = AlertItem(
                            title: String(localized: "Backup Failed"),
                            message: String(localized: "Error: ") + error.localizedDescription,
                            type: .error
                        )
                    }
                }
            }
        }
        
        // Start async initialization of services
        // Note: refreshStats() is called inside initializeServices() after database connection
        // Start async initialization of services
        // Note: refreshStats() is called inside initializeServices() after database connection
        initializeServices()
        
        // Resume auto backup if enabled
        if config.autoBackupEnabled {
            scheduler?.startAutoBackup()
        }
    }

    /// Perform startup permission and account checks with logging
    func performStartupChecks() {
        // Trigger permission check explicitly
        PermissionHelper.shared.refreshPermissionStatus()
        
        addLog(String(localized: "🚀 Starting permission checks..."), type: .info)
        
        // Check Full Disk Access (Messages & Call History database)
        if messagesDbConnected {
            addLog(String(localized: "✅ Messages database: Connected"), type: .success)
        } else {
            addLog(String(localized: "⚠️ Messages database: No access - Need Full Disk Access permission"), type: .warning)
        }
        
        if callHistoryDbConnected {
            addLog(String(localized: "✅ Call history database: Connected"), type: .success)
        } else {
            addLog(String(localized: "⚠️ Call history database: No access - Need Full Disk Access permission"), type: .warning)
        }
        
        // Check Gmail account
        if !config.email.isEmpty, let service = imapService {
            if service.hasPassword {
                addLog(String(localized: "✅ Gmail account: ") + config.email, type: .success)
                addLog(String(localized: "✅ Gmail App Password: Configured"), type: .success)
                gmailConnected = true
            } else {
                addLog(String(localized: "✅ Gmail account: ") + config.email, type: .success)
                addLog(String(localized: "⚠️ Gmail App Password: Not configured"), type: .warning)
                gmailConnected = false
            }
        } else {
            addLog(String(localized: "⚠️ Gmail account: Not configured"), type: .warning)
            gmailConnected = false
        }
        
        // Check Calendar access
        let calendarService = LocalCalendarService.shared
        if calendarService.isAuthorized {
            addLog(String(localized: "✅ Calendar access: Authorized"), type: .success)
            calendarConnected = true
        } else {
            addLog(String(localized: "ℹ️ Calendar access: Not authorized (Enable in Settings if needed)"), type: .info)
            calendarConnected = false
            // Do NOT request access automatically on startup
        }
        
        addLog(String(localized: "✅ Startup checks completed"), type: .success)
    }
    
    func refreshStats() {
        // Safety check: only refresh stats when at least one database is connected
        guard messageService.isConnected || callService.isConnected else {
            return
        }
        
        // Use DispatchQueue instead of Task to avoid SQLite thread safety issues
        // SQLite connections must be used from the same thread they were created on
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let msgCount = try self.messageService.getMessageCount()
                let callCount = try self.callService.getRecordCount()
                
                // Calculate backed up and remaining based on lastRowId
                // This is an approximation since rowIds may not be sequential
                let msgsSinceLastBackup = try self.messageService.getMessageCount(sinceRowId: self.config.lastMessageRowId)
                let callsSinceLastBackup = try self.callService.getRecordCount(sinceRowId: self.config.lastCallRecordRowId)
                
                DispatchQueue.main.async {
                    self.totalMessages = msgCount
                    self.totalCallRecords = callCount
                    self.remainingMessages = msgsSinceLastBackup
                    self.remainingCallRecords = callsSinceLastBackup
                    self.backedUpMessages = max(0, msgCount - msgsSinceLastBackup)
                    self.backedUpCallRecords = max(0, callCount - callsSinceLastBackup)
                }
            } catch {
                print("Failed to get stats: \(error)")
            }
        }
    }
    
    func startBackup() {
        isBackingUp = true
        statusMessage = String(localized: "Starting backup...")
        
        // Save current stats for real-time update calculation
        backupStartBackedUpMessages = backedUpMessages
        backupStartBackedUpCalls = backedUpCallRecords
        
        Task {
            await scheduler?.performBackup()
        }
    }
    
    func cancelBackup() {
        scheduler?.cancelBackup()
        isBackingUp = false
        
        // Reload config to get latest progress saved by BackupScheduler
        config = BackupConfig.load()
        
        // Refresh stats to update UI with saved progress
        refreshStats()
        
        statusMessage = String(localized: "Backup cancelled")
        addLog(String(localized: "Backup cancelled"), type: .warning)
    }
    
    func saveConfig() {
        do {
            try config.save()
            imapService = IMAPService(config: config)
            scheduler?.updateConfig(config)
            // Also sync the IMAPService so scheduler uses the one with cached password
            if let service = imapService {
                scheduler?.updateIMAPService(service)
            }
        } catch {
            statusMessage = "Failed to save config: \(error.localizedDescription)"
        }
    }
    
    /// Refresh database connections (called after permission granted)
    func initializeServices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Connect databases asynchronously
            self.messageService.connect()
            self.callService.connect()
            
            let msgConnected = self.messageService.isConnected
            let callConnected = self.callService.isConnected
            
            // Load initial counts if connected
            var msgCount = 0
            var callCount = 0
            
            if msgConnected {
                msgCount = (try? self.messageService.getMessageCount()) ?? 0
            }
            if callConnected {
                callCount = (try? self.callService.getRecordCount()) ?? 0
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.messagesDbConnected = msgConnected
                self.callHistoryDbConnected = callConnected
                self.totalMessages = msgCount
                self.totalCallRecords = callCount
                // Must ensure services are synced with scheduler too
                if let scheduler = self.scheduler {
                    scheduler.updateServices(messageService: self.messageService, callService: self.callService)
                }
                self.refreshStats()
                self.performStartupChecks()
            }
        }
    }

    func refreshDatabaseConnections() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Attempt to connect existing services if not connected
            if !self.messageService.isConnected {
                self.messageService.connect()
            }
            if !self.callService.isConnected {
                self.callService.connect()
            }
            
            let msgConnected = self.messageService.isConnected
            let callConnected = self.callService.isConnected
            
            DispatchQueue.main.async {
                // Update connection status
                self.messagesDbConnected = msgConnected
                self.callHistoryDbConnected = callConnected
                
                // Update scheduler services to ensure it uses the connected instances
                if let scheduler = self.scheduler {
                    scheduler.updateServices(messageService: self.messageService, callService: self.callService)
                }
                
                // Refresh stats if connected
                if msgConnected || callConnected {
                    self.refreshStats()
                }
            }
        }
    }

    
    /// Verify Gmail connection via real network test
    func verifyGmailConnection() async {
        guard !config.email.isEmpty, let service = imapService else {
            await MainActor.run {
                gmailConnected = false
            }
            return
        }
        
        do {
            let success = try await service.testConnection()
            await MainActor.run {
                gmailConnected = success
                if success {
                    addLog(String(localized: "✅ Gmail connection verified"), type: .success)
                } else {
                    addLog(String(localized: "❌ Gmail connection check failed"), type: .error)
                }
            }
        } catch {
            await MainActor.run {
                gmailConnected = false
                // Use String(format:) for dynamic error message localization
                let errorMsg = String(format: String(localized: "Gmail check error: %@"), error.localizedDescription)
                addLog(errorMsg, type: .error)
            }
        }
    }
    
    /// Lightweight sync check for Settings save
    func refreshGmailStatus() {
        if !config.email.isEmpty, let service = imapService {
            // Only checks keychain existence, not network
            gmailConnected = service.hasPassword
        } else {
            gmailConnected = false
        }
    }
    
    /// Refresh Calendar connection status
    func refreshCalendarStatus() {
        // Connected only if authorized AND a calendar is selected
        let authorized = LocalCalendarService.shared.isAuthorized
        let calendarSelected = !config.calendarId.isEmpty
        calendarConnected = authorized && calendarSelected
    }

    /// Start test backup with mock data
    func startTestBackup() {
        isBackingUp = true
        statusMessage = "Running test..."
        addLog("Starting test backup...", type: .info)
        
        Task {
            await scheduler?.performTestBackup()
            await MainActor.run {
                isBackingUp = false
                statusMessage = "Test completed"
                addLog("Test backup completed", type: .success)
                
                // Show test completion alert
                activeAlert = AlertItem(
                    title: String(localized: "Test Complete"),
                    message: String(localized: "Test backup executed successfully. Check the operation log for details."),
                    type: .success
                )
            }
        }
    }
}

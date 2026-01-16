import Foundation

/// Backup scheduler for automatic backups
class BackupScheduler {
    
    private var timer: Timer?
    private var config: BackupConfig
    private var messageService: MessageDatabaseService
    private var callService: CallHistoryService
    private var imapService: IMAPService?
    private let localCalendarService = LocalCalendarService.shared
    
    /// Flag to cancel ongoing backup
    private var isCancelled = false
    
    /// Callback for backup progress updates (percentage 0-1, message)
    var onProgress: ((Double, String) -> Void)?
    
    /// Callback for backup completion (result, isAutoBackup)
    var onComplete: ((Result<BackupResult, Error>, Bool) -> Void)?
    
    /// Callback for incremental progress updates (messagesBackedUp, callsBackedUp)
    var onIncrementalUpdate: ((Int, Int) -> Void)?
    
    init(config: BackupConfig) {
        self.config = config
        self.messageService = MessageDatabaseService()
        self.callService = CallHistoryService()
        self.imapService = IMAPService(config: config)
    }
    
    /// Update services (e.g. after permissions granted)
    func updateServices(messageService: MessageDatabaseService, callService: CallHistoryService) {
        self.messageService = messageService
        self.callService = callService
    }
    
    /// Start automatic backup scheduler
    func startAutoBackup() {
        guard config.autoBackupEnabled else { return }
        
        let interval = TimeInterval(config.autoBackupIntervalMinutes * 60)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.performBackup(isAutoBackup: true)
            }
        }
        
        Logger.shared.info("✅ Auto backup started (every \(config.autoBackupIntervalMinutes) minutes)")
    }
    
    /// Stop automatic backup
    func stopAutoBackup() {
        timer?.invalidate()
        timer = nil
        Logger.shared.info("⏹ Auto backup stopped")
    }
    
    /// Cancel ongoing backup
    func cancelBackup() {
        isCancelled = true
    }
    
    /// Perform a backup now
    @MainActor
    func performBackup(isAutoBackup: Bool = false) async {
        isCancelled = false  // Reset cancel flag
        Logger.shared.info("Starting backup... (isAutoBackup: \(isAutoBackup))")
        onProgress?(0.0, String(localized: "Starting backup..."))
        
        var result = BackupResult()
        
        do {
            // Backup messages
            if config.backupMessages && !isCancelled {
                onProgress?(0.05, String(localized: "Reading messages..."))
                let messages = try messageService.fetchMessages(sinceRowId: config.lastMessageRowId, limit: Int.max)
                result.messagesFound = messages.count
                
                if !messages.isEmpty, let imapService = imapService {
                    let backingUpMsg = String(format: String(localized: "Backing up %d messages..."), messages.count)
                    onProgress?(0.1, backingUpMsg)
                    
                    var lastSuccessfulId: Int64 = config.lastMessageRowId
                    var backedUpCount = 0
                    
                    try await imapService.backupMessages(messages) { current, total, messageId in
                        // Check if cancelled
                        if self.isCancelled {
                            return  // This will stop the backup loop in IMAPService
                        }
                        
                        // Save progress immediately after every successful message
                        self.config.lastMessageRowId = messageId
                        self.config.lastMessageBackupDate = Date()
                        try? self.config.save()
                        
                        // Update UI for every item for real-time feedback
                        Task { @MainActor in
                            let stepProgress = Double(current) / Double(total)
                            let totalProgress = 0.1 + (stepProgress * 0.4)
                            let progressMsg = String(format: String(localized: "✅ Message %d/%d backed up"), current, total)
                            self.onProgress?(totalProgress, progressMsg)
                            
                            // Call incremental update callback
                            self.onIncrementalUpdate?(current, 0)
                        }
                    }
                    
                    result.messagesBackedUp = messages.count
                }
            }
            
            // Backup call records
            if config.backupCallLog && !isCancelled {
                onProgress?(0.5, String(localized: "Reading call history..."))
                let records = try callService.fetchCallRecords(sinceRowId: config.lastCallRecordRowId, limit: Int.max)
                result.callRecordsFound = records.count
                
                if !records.isEmpty, let imapService = imapService {
                    let backingUpMsg = String(format: String(localized: "Backing up %d call records..."), records.count)
                    onProgress?(0.55, backingUpMsg)
                    
                    var lastSuccessfulId: Int64 = config.lastCallRecordRowId
                    var backedUpCount = 0
                    
                    try await imapService.backupCallRecords(records) { current, total, recordId in
                        // Check if cancelled
                        if self.isCancelled {
                            return
                        }
                        
                        // Save progress immediately after every successful call record
                        self.config.lastCallRecordRowId = recordId
                        self.config.lastCallLogBackupDate = Date()
                        try? self.config.save()
                        
                        // Update UI for every item for real-time feedback
                        Task { @MainActor in
                            let stepProgress = Double(current) / Double(total)
                            let totalProgress = 0.55 + (stepProgress * 0.25)
                            let progressMsg = String(format: String(localized: "✅ Call record %d/%d backed up"), current, total)
                            self.onProgress?(totalProgress, progressMsg)
                            
                            // Call incremental update callback (messages count, calls count)
                            self.onIncrementalUpdate?(result.messagesBackedUp, current)
                        }
                    }
                    
                    result.callRecordsBackedUp = records.count
                }
                
                // Sync to local macOS Calendar if enabled
                if config.calendarSyncEnabled && localCalendarService.isAuthorized {
                    // Update service with selected calendar from config
                    await MainActor.run {
                        localCalendarService.selectedCalendarId = config.calendarId
                    }
                    
                    let recordsToSync = try callService.fetchCallRecords(sinceRowId: config.lastCalendarSyncRowId, limit: Int.max)
                    
                    if !recordsToSync.isEmpty {
                        let syncingMsg = String(format: String(localized: "Syncing %d calls to Calendar..."), recordsToSync.count)
                        onProgress?(0.8, syncingMsg)
                        
                        do {
                            let syncedCount = try await localCalendarService.createCallEvents(recordsToSync) { current, total in
                                Task { @MainActor in
                                    let stepProgress = Double(current) / Double(total)
                                    // Map this to 80% -> 100% range of total progress
                                    let totalProgress = 0.8 + (stepProgress * 0.2)
                                    let progressMsg = String(format: String(localized: "Syncing to calendar: %d/%d"), current, total)
                                    self.onProgress?(totalProgress, progressMsg)
                                }
                            }
                            
                            result.calendarEventsSynced = syncedCount
                            
                            if let lastRecord = recordsToSync.last {
                                config.lastCalendarSyncRowId = lastRecord.id
                            }
                            
                            Logger.shared.info("✅ Synced \(syncedCount) call events to Calendar")
                        } catch {
                            Logger.shared.warning("⚠️ Calendar sync failed: \(error.localizedDescription)")
                            // Don't fail the whole backup if calendar sync fails
                        }
                    }
                }
            }
            
            // Save updated config
            try config.save()
            
            // Check if backup was cancelled
            if isCancelled {
                onProgress?(0.0, String(localized: "Backup cancelled"))
                onComplete?(.failure(BackupError.cancelled), isAutoBackup)
                return
            }
            
            Logger.shared.info("Backup complete! \(result.summary)")
            onProgress?(1.0, String(localized: "Backup complete!"))
            onComplete?(.success(result), isAutoBackup)
            
        } catch {
            let failedMsg = String(localized: "Backup failed: \(error.localizedDescription)")
            Logger.shared.error(failedMsg)
            onProgress?(0.0, failedMsg)
            onComplete?(.failure(error), isAutoBackup)
        }
    }
    
    /// Update configuration
    func updateConfig(_ newConfig: BackupConfig) {
        self.config = newConfig
        self.imapService = IMAPService(config: newConfig)
    }
    
    /// Update IMAP service (e.g. after credentials saved)
    func updateIMAPService(_ service: IMAPService) {
        self.imapService = service
    }
    
    /// Perform a quick test backup with mock data
    @MainActor
    func performTestBackup() async {
        onProgress?(0.0, String(localized: "Creating test data..."))
        
        // Create test SMS message
        let testMessage = Message(
            id: -1,
            guid: "test-\(UUID().uuidString)",
            text: "🧪 This is a test SMS message from MacMessageBackup at \(Date().formatted())",
            date: Date(),
            isFromMe: false,
            handleId: "+8613800138000",
            chatId: "test-chat",
            service: "iMessage",
            hasAttachments: false
        )
        
        // Create test call record
        let testCallRecord = CallRecord(
            id: -1,
            address: "+8613800138000",
            date: Date(),
            duration: 65,
            callType: .incoming,
            isRead: true,
            service: "FaceTime"
        )
        
        var result = BackupResult()
        result.messagesFound = 1
        result.callRecordsFound = 1
        
        // Test SMS backup
        if config.backupMessages, let imapService = imapService {
            onProgress?(0.2, String(localized: "Testing SMS backup..."))
            do {
                try await imapService.backupMessages([testMessage]) { _, _, _ in }
                result.messagesBackedUp = 1
                Logger.shared.info("✅ Test SMS saved to Gmail")
            } catch {
                Logger.shared.error("❌ SMS test failed: \(error)")
            }
        }
        
        // Test Call Log backup
        if config.backupCallLog, let imapService = imapService {
            onProgress?(0.5, String(localized: "Testing call log backup..."))
            do {
                try await imapService.backupCallRecords([testCallRecord]) { _, _, _ in }
                result.callRecordsBackedUp = 1
                Logger.shared.info("✅ Test call record saved to Gmail")
            } catch {
                Logger.shared.error("❌ Gmail test failed: \(error)")
            }
        }
        
        // Test Calendar sync
        if config.calendarSyncEnabled && localCalendarService.isAuthorized {
            onProgress?(0.8, String(localized: "Testing Calendar sync..."))
            do {
                try localCalendarService.createCallEvent(testCallRecord)
                result.calendarEventsSynced = 1
                Logger.shared.info("✅ Test calendar event created")
            } catch {
                Logger.shared.error("❌ Calendar test failed: \(error)")
            }
        }
        
        onProgress?(1.0, String(localized: "Test complete!"))
        onComplete?(.success(result), false)
    }
}

/// Backup result summary
struct BackupResult {
    var messagesFound: Int = 0
    var messagesBackedUp: Int = 0
    var callRecordsFound: Int = 0
    var callRecordsBackedUp: Int = 0
    var calendarEventsSynced: Int = 0
    
    var summary: String {
        var parts: [String] = []
        
        if messagesBackedUp > 0 {
            parts.append(String(format: String(localized: "%d messages"), messagesBackedUp))
        }
        if callRecordsBackedUp > 0 {
            parts.append(String(format: String(localized: "%d call records"), callRecordsBackedUp))
        }
        if calendarEventsSynced > 0 {
            parts.append(String(format: String(localized: "%d calendar events"), calendarEventsSynced))
        }
        
        if parts.isEmpty {
            return String(localized: "No new messages or call records found")
        }
        
        return String(localized: "Backed up: ") + parts.joined(separator: ", ")
    }
}

/// Backup errors
enum BackupError: Error, LocalizedError {
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "Backup was cancelled")
        }
    }
}
